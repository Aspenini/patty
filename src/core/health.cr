require "socket"
require "uri"

module Patty::Core::Health
  enum State
    Healthy
    Unhealthy
    Unknown
    Disabled

    def label : String
      to_s.downcase
    end

    def css_class : String
      case self
      in .healthy?   then "ok"
      in .unhealthy? then "error"
      in .unknown?   then "warn"
      in .disabled?  then "off"
      end
    end
  end

  record Check, state : State, label : String, detail : String

  module Checker
    CONNECT_TIMEOUT = 300.milliseconds
    CACHE_TTL       = 5.seconds

    @@cache = {} of String => {Time::Instant, Check}
    @@mutex = Mutex.new

    def self.check(profile : Profile, route_enabled : Bool, caddy_running : Bool) : Check
      key = "#{profile.slug}:#{route_enabled}:#{caddy_running}:#{profile.caddy.hash}"
      now = Time.instant
      if cached = @@mutex.synchronize { @@cache[key]? }
        return cached[1] if now - cached[0] < CACHE_TTL
      end

      result = perform(profile, route_enabled, caddy_running)
      @@mutex.synchronize { @@cache[key] = {now, result} }
      result
    end

    def self.reset!
      @@mutex.synchronize { @@cache.clear }
    end

    private def self.perform(profile : Profile, route_enabled : Bool, caddy_running : Bool) : Check
      return Check.new(State::Disabled, "disabled", "The Caddy route is disabled.") unless route_enabled
      return Check.new(State::Unhealthy, "Caddy stopped", "The route cannot serve traffic because Caddy is not running.") unless caddy_running

      if endpoint = reverse_proxy_endpoint(profile.caddy)
        host, port = endpoint
        if tcp_reachable?(host, port)
          return Check.new(State::Healthy, "backend reachable", "#{host}:#{port} accepted a connection.")
        end
        return Check.new(State::Unhealthy, "backend down", "Could not connect to #{host}:#{port}.")
      end

      if root = file_server_root(profile.caddy)
        if Dir.exists?(root)
          return Check.new(State::Healthy, "root available", "#{root} is accessible.")
        end
        return Check.new(State::Unhealthy, "root missing", "#{root} is not an accessible directory.")
      end

      Check.new(State::Healthy, "route active", "The route is loaded and Caddy is running.")
    end

    private def self.reverse_proxy_endpoint(snippet : String) : {String, Int32}?
      snippet.each_line(chomp: true) do |line|
        stripped = line.strip
        next if stripped.starts_with?('#')
        match = stripped.match(/\Areverse_proxy\s+([^\s{]+)(?:\s|\z)/)
        next unless match
        return parse_endpoint(match[1])
      end
      nil
    end

    private def self.parse_endpoint(target : String) : {String, Int32}?
      if target.includes?("://")
        uri = URI.parse(target)
        host = uri.host
        return nil unless host
        port = uri.port || (uri.scheme == "https" ? 443 : 80)
        return {host, port}
      end

      return nil if target.starts_with?("unix/") || target.includes?('{')
      separator = target.rindex(':')
      return nil unless separator
      host = target[0, separator].lstrip('[').rstrip(']')
      port = target[separator + 1..].to_i?
      return nil if host.empty? || port.nil?
      {host, port}
    rescue URI::Error
      nil
    end

    private def self.file_server_root(snippet : String) : String?
      has_file_server = snippet.each_line.any? { |line| line.strip.starts_with?("file_server") }
      return nil unless has_file_server

      snippet.each_line(chomp: true) do |line|
        stripped = line.strip
        next if stripped.starts_with?('#')
        match = stripped.match(/\Aroot(?:\s+\*)?\s+(.+)\z/)
        next unless match
        value = match[1].strip
        if value.starts_with?('"') && value.ends_with?('"') && value.size >= 2
          return value[1...-1]
        end
        return value.split(/\s+/).first?
      end
      nil
    end

    private def self.tcp_reachable?(host : String, port : Int32) : Bool
      socket = TCPSocket.new(host, port, connect_timeout: CONNECT_TIMEOUT)
      socket.close
      true
    rescue
      false
    end
  end
end
