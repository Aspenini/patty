require "http/client"

module Patty::Caddy
  abstract class Runtime
    abstract def found? : Bool
    abstract def running? : Bool
    abstract def validate(config_path : String) : Result
    abstract def reload(config_path : String) : Result
  end

  class SystemRuntime < Runtime
    ADMIN_HOST = "127.0.0.1"
    ADMIN_PORT = 2019

    def found? : Bool
      !Util::ProcessRunner.which(binary).nil?
    end

    def running? : Bool
      client = HTTP::Client.new(ADMIN_HOST, ADMIN_PORT)
      client.connect_timeout = 1.seconds
      client.read_timeout = 2.seconds
      begin
        client.get("/config/").status_code < 500
      rescue
        false
      ensure
        client.close
      end
    end

    def validate(config_path : String) : Result
      unless found?
        return Result.failure("Caddy binary \"#{binary}\" not found.",
          "Install Caddy or set the binary path on the Settings page.")
      end

      res = Util::ProcessRunner.run(binary, ["validate", "--config", config_path, "--adapter", "caddyfile"])
      if res.success?
        Result.success("Caddy validation passed.")
      else
        Result.failure("Caddy validation failed.", res.output)
      end
    end

    def reload(config_path : String) : Result
      unless found?
        return Result.failure("Caddy binary \"#{binary}\" not found.",
          "Install Caddy or set the binary path on the Settings page.")
      end
      unless running?
        return Result.failure("Caddy is not running, so it was not reloaded.",
          "Start it with: #{binary} run --config \"#{config_path}\" --adapter caddyfile")
      end

      res = Util::ProcessRunner.run(binary, ["reload", "--config", config_path, "--adapter", "caddyfile"])
      if res.success?
        Result.success("Caddy reload succeeded.")
      else
        Result.failure("Caddy reload failed.", res.output)
      end
    end

    private def binary : String
      Config.instance.caddy.binary
    end
  end

  @@runtime : Runtime?

  def self.runtime : Runtime
    @@runtime ||= SystemRuntime.new
  end

  def self.runtime=(runtime : Runtime)
    @@runtime = runtime
  end

  def self.reset_runtime!
    @@runtime = nil
  end
end
