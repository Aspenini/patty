module Patty::Services
  # Controls services registered with the Windows Service Control Manager.
  class WindowsServiceAdapter < Adapter
    POLL_ATTEMPTS = 40

    def name : String
      "Windows service"
    end

    def available?(program : String) : Bool
      query(program).success?
    end

    def start(program : String) : Result
      return Result.success("Windows service #{program} is already running.") if status(program).running?
      run_action("start", program, Status::Running)
    end

    def stop(program : String) : Result
      return Result.success("Windows service #{program} is already stopped.") if status(program).stopped?
      run_action("stop", program, Status::Stopped)
    end

    def restart(program : String) : Result
      stopped = stop(program)
      return stopped unless stopped.ok?
      start(program)
    end

    def status(program : String) : Status
      result = query(program)
      return Status::NotFound unless result.success?

      output = result.stdout.upcase
      return Status::Running if output.includes?("RUNNING")
      return Status::Stopped if output.includes?("STOPPED")
      Status::Unknown
    end

    private def run_action(action : String, program : String, desired : Status) : Result
      result = execute("sc.exe", [action, program])
      unless result.success?
        return Result.failure("Could not #{action} Windows service #{program}.", result.output)
      end

      POLL_ATTEMPTS.times do
        current = status(program)
        if current == desired
          return Result.success("Windows service #{program} #{desired.running? ? "started" : "stopped"}.")
        end
        pause
      end

      Result.failure(
        "Windows service #{program} did not reach #{desired.label}.",
        "Check the service in Windows Services and review Patty's logs."
      )
    end

    private def query(program : String) : Util::CommandResult
      execute("sc.exe", ["query", program])
    end

    protected def execute(command : String, args : Array(String)) : Util::CommandResult
      Util::ProcessRunner.run(command, args)
    end

    protected def pause
      sleep 250.milliseconds
    end
  end
end
