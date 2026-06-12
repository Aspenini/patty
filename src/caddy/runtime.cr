require "socket"

module Patty::Caddy
  abstract class Runtime
    abstract def found? : Bool
    abstract def running? : Bool
    abstract def validate(config_path : String) : Result
    abstract def start(config_path : String) : Result
    abstract def reload(config_path : String) : Result
  end

  class SystemRuntime < Runtime
    ADMIN_HOST = "127.0.0.1"
    ADMIN_PORT = 2019

    def found? : Bool
      !Util::ProcessRunner.which(binary).nil?
    end

    def running? : Bool
      socket = TCPSocket.new(ADMIN_HOST, ADMIN_PORT, connect_timeout: 1.second)
      socket.close
      true
    rescue
      false
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

    def start(config_path : String) : Result
      unless found?
        return Result.failure("Caddy binary \"#{binary}\" not found.",
          "Install Caddy or set the binary path on the Settings page.")
      end

      Util::ActionLog.rotate_caddy_before_start!
      args = [
        Util::Platform.windows? ? "run" : "start",
        "--config", config_path,
        "--adapter", "caddyfile",
      ]
      res =
        if Util::Platform.windows?
          Util::ProcessRunner.start_logged(binary, args, Util::Paths.caddy_log_file)
        else
          Util::ProcessRunner.run_logged(binary, args, Util::Paths.caddy_log_file)
        end
      unless res.success?
        return Result.failure("Caddy could not be started.", startup_detail(res))
      end

      30.times do
        return Result.success("Caddy started.") if running?
        sleep 100.milliseconds
      end

      Result.failure("Caddy was launched, but its admin API did not become ready.", startup_detail(res))
    end

    def reload(config_path : String) : Result
      unless found?
        return Result.failure("Caddy binary \"#{binary}\" not found.",
          "Install Caddy or set the binary path on the Settings page.")
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

    private def startup_detail(result : Util::CommandResult) : String
      result.output.presence || "See #{Util::Paths.caddy_log_file}"
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
