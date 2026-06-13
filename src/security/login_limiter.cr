module Patty::Security
  class LoginLimiter
    PER_IP_CAPACITY   = 5.0
    PER_IP_REFILL     = 1.0 / 60.0
    GLOBAL_CAPACITY   = 20.0
    GLOBAL_REFILL     = 1.0 / 10.0
    COOLDOWN_FAILURES = 10
    COOLDOWN          = 15.minutes
    ENTRY_TTL         = 1.hour
    MAX_ENTRIES       = 10_000

    record Decision, allowed : Bool, retry_after : Int32

    private class Bucket
      property tokens : Float64
      property updated_at : Time
      property failures : Int32
      property cooldown_until : Time?
      property last_seen : Time

      def initialize(@tokens : Float64, now : Time)
        @updated_at = now
        @last_seen = now
        @failures = 0
      end
    end

    @entries = {} of String => Bucket
    @global = Bucket.new(GLOBAL_CAPACITY, Time.utc)
    @mutex = Mutex.new

    def check(ip : String, now : Time = Time.utc) : Decision
      @mutex.synchronize do
        cleanup(now)
        entry = @entries[ip]? || begin
          enforce_bound
          @entries[ip] = Bucket.new(PER_IP_CAPACITY, now)
        end
        entry.last_seen = now

        if cooldown = entry.cooldown_until
          if cooldown > now
            return Decision.new(false, Math.max(1, (cooldown - now).total_seconds.ceil.to_i))
          end
          entry.cooldown_until = nil
          entry.failures = 0
        end

        refill(entry, PER_IP_CAPACITY, PER_IP_REFILL, now)
        refill(@global, GLOBAL_CAPACITY, GLOBAL_REFILL, now)
        per_ip_wait = wait_seconds(entry, PER_IP_REFILL)
        global_wait = wait_seconds(@global, GLOBAL_REFILL)
        if per_ip_wait > 0 || global_wait > 0
          return Decision.new(false, Math.max(per_ip_wait, global_wait))
        end

        entry.tokens -= 1.0
        @global.tokens -= 1.0
        Decision.new(true, 0)
      end
    end

    def failure!(ip : String, now : Time = Time.utc)
      @mutex.synchronize do
        entry = @entries[ip]? || (@entries[ip] = Bucket.new(PER_IP_CAPACITY, now))
        entry.failures += 1
        entry.last_seen = now
        if entry.failures >= COOLDOWN_FAILURES
          entry.cooldown_until = now + COOLDOWN
        end
      end
    end

    def success!(ip : String)
      @mutex.synchronize do
        if entry = @entries[ip]?
          entry.failures = 0
          entry.cooldown_until = nil
        end
      end
    end

    def reset!
      @mutex.synchronize do
        @entries.clear
        @global = Bucket.new(GLOBAL_CAPACITY, Time.utc)
      end
    end

    private def refill(bucket : Bucket, capacity : Float64, rate : Float64, now : Time)
      elapsed = Math.max(0.0, (now - bucket.updated_at).total_seconds)
      bucket.tokens = Math.min(capacity, bucket.tokens + elapsed * rate)
      bucket.updated_at = now
    end

    private def wait_seconds(bucket : Bucket, rate : Float64) : Int32
      return 0 if bucket.tokens >= 1.0
      Math.max(1, ((1.0 - bucket.tokens) / rate).ceil.to_i)
    end

    private def cleanup(now : Time)
      @entries.reject! do |_ip, entry|
        (now - entry.last_seen) > ENTRY_TTL &&
          entry.cooldown_until.try { |cooldown| cooldown <= now } != false
      end
    end

    private def enforce_bound
      return if @entries.size < MAX_ENTRIES
      oldest = @entries.min_by? { |_ip, entry| entry.last_seen }
      @entries.delete(oldest.not_nil![0]) if oldest
    end
  end
end
