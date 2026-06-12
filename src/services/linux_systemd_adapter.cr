module Patty::Services
  # Controls system services registered with systemd.
  class LinuxSystemdAdapter < Adapter
    def name : String
      "Linux systemd service"
    end

    def available?(program : String) : Bool
      result = execute("systemctl", ["show", unit_name(program), "--property=LoadState", "--value"])
      result.success? && result.stdout.strip == "loaded"
    end

    def start(program : String) : Result
      run_action("start", program)
    end

    def stop(program : String) : Result
      run_action("stop", program)
    end

    def restart(program : String) : Result
      run_action("restart", program)
    end

    def status(program : String) : Status
      return Status::NotFound unless available?(program)

      result = execute("systemctl", ["is-active", unit_name(program)])
      case result.stdout.strip
      when "active", "reloading"
        Status::Running
      when "inactive", "failed", "deactivating"
        Status::Stopped
      else
        Status::Unknown
      end
    end

    private def run_action(action : String, program : String) : Result
      unit = unit_name(program)
      result = execute("systemctl", [action, unit])
      if result.success?
        Result.success("systemctl #{action} #{unit} succeeded.")
      else
        Result.failure("systemctl #{action} #{unit} failed.", result.output)
      end
    end

    private def unit_name(program : String) : String
      program.ends_with?(".service") ? program : "#{program}.service"
    end

    protected def execute(command : String, args : Array(String)) : Util::CommandResult
      Util::ProcessRunner.run(command, args)
    end
  end
end
