# Single choke point for running external commands. Always takes an argument
# array and never goes through a shell, so profile data can't inject commands.
module Patty::Util
  record CommandResult, exit_code : Int32, stdout : String, stderr : String do
    def success? : Bool
      exit_code == 0
    end

    def output : String
      stderr.strip.empty? ? stdout.strip : stderr.strip
    end
  end

  module ProcessRunner
    def self.run(command : String, args : Array(String)) : CommandResult
      stdout = IO::Memory.new
      stderr = IO::Memory.new
      status = Process.run(command, args, output: stdout, error: stderr)
      code = status.normal_exit? ? status.exit_code : 128
      CommandResult.new(code, stdout.to_s, stderr.to_s)
    rescue ex : IO::Error
      CommandResult.new(127, "", "#{command}: #{ex.message}")
    end

    def self.which(command : String) : String?
      return command if command.includes?(File::SEPARATOR) && File::Info.executable?(command)
      Process.find_executable(command)
    end
  end
end
