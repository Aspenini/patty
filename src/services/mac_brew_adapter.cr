module Patty::Services
  # Controls programs installed as Homebrew services.
  # `brew services list` is slow (~1s), so the parsed list is cached briefly.
  class MacBrewAdapter < Adapter
    CACHE_TTL = 5.seconds

    @list_cache : Hash(String, String)?
    @cached_at : Time?
    @mutex = Mutex.new

    def name : String
      "macOS Homebrew service"
    end

    def available?(program : String) : Bool
      services_list.has_key?(program)
    end

    def start(program : String) : Result
      run_brew("start", program)
    end

    def stop(program : String) : Result
      run_brew("stop", program)
    end

    def restart(program : String) : Result
      run_brew("restart", program)
    end

    def status(program : String) : Status
      case services_list[program]?
      when nil
        Status::NotFound
      when "started", "scheduled"
        Status::Running
      when "none", "stopped"
        Status::Stopped
      else # "error", "unknown", anything new
        Status::Unknown
      end
    end

    private def run_brew(action : String, program : String) : Result
      invalidate_cache
      res = Util::ProcessRunner.run("brew", ["services", action, program])
      if res.success?
        Result.success("brew services #{action} #{program} succeeded.")
      else
        Result.failure("brew services #{action} #{program} failed.", res.output)
      end
    end

    private def services_list : Hash(String, String)
      @mutex.synchronize do
        if (cached = @list_cache) && (at = @cached_at) && (Time.utc - at) < CACHE_TTL
          return cached
        end
        map = {} of String => String
        res = Util::ProcessRunner.run("brew", ["services", "list"])
        if res.success?
          res.stdout.each_line do |line|
            next if line.strip.empty? || line.starts_with?("Name")
            parts = line.split
            next if parts.empty?
            map[parts[0]] = parts[1]? || "unknown"
          end
        end
        @list_cache = map
        @cached_at = Time.utc
        map
      end
    end

    private def invalidate_cache
      @mutex.synchronize { @list_cache = nil }
    end
  end
end
