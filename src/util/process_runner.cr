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
      {% if flag?(:windows) %}
        run_hidden(command, args)
      {% else %}
        stdout = IO::Memory.new
        stderr = IO::Memory.new
        status = Process.run(command, args, output: stdout, error: stderr)
        code = status.normal_exit? ? status.exit_code : 128
        CommandResult.new(code, stdout.to_s, stderr.to_s)
      {% end %}
    rescue ex : IO::Error
      CommandResult.new(127, "", "#{command}: #{ex.message}")
    end

    # Background-launching commands must write to a real file. Capturing them
    # with pipes can hang when the spawned child inherits those pipe handles.
    def self.run_logged(command : String, args : Array(String), log_path : String) : CommandResult
      Dir.mkdir_p(File.dirname(log_path))
      File.open(log_path, "a") do |log|
        log.puts "\n[#{Time.local.to_s("%Y-%m-%d %H:%M:%S")}] #{command} #{args.join(' ')}"
        log.flush
        {% if flag?(:windows) %}
          code = run_hidden_status(command, args, log, log)
          CommandResult.new(code, "", "")
        {% else %}
          status = Process.run(command, args, output: log, error: log)
          code = status.normal_exit? ? status.exit_code : 128
          CommandResult.new(code, "", "")
        {% end %}
      end
    rescue ex : IO::Error
      CommandResult.new(127, "", "#{command}: #{ex.message}")
    end

    def self.start_logged(command : String, args : Array(String), log_path : String) : CommandResult
      Dir.mkdir_p(File.dirname(log_path))
      File.open(log_path, "a") do |log|
        log.puts "\n[#{Time.local.to_s("%Y-%m-%d %H:%M:%S")}] #{command} #{args.join(' ')}"
        log.flush
        {% if flag?(:windows) %}
          process_info = start_hidden(command, args, log, log)
          LibC.CloseHandle(process_info.hThread)
          LibC.CloseHandle(process_info.hProcess)
        {% else %}
          Process.new(command, args, output: log, error: log)
        {% end %}
      end
      CommandResult.new(0, "", "")
    rescue ex : IO::Error
      CommandResult.new(127, "", "#{command}: #{ex.message}")
    end

    def self.which(command : String) : String?
      return command if command.includes?(File::SEPARATOR) && File::Info.executable?(command)
      Process.find_executable(command)
    end

    {% if flag?(:windows) %}
      DETACHED_PROCESS = 0x00000008_u32

      private def self.run_hidden(command : String, args : Array(String)) : CommandResult
        stdout_path = File.tempname("patty-stdout")
        stderr_path = File.tempname("patty-stderr")
        begin
          File.open(stdout_path, "w+") do |stdout|
            File.open(stderr_path, "w+") do |stderr|
              code = run_hidden_status(command, args, stdout, stderr)
              stdout.flush
              stderr.flush
              stdout.rewind
              stderr.rewind
              CommandResult.new(code, stdout.gets_to_end, stderr.gets_to_end)
            end
          end
        ensure
          File.delete(stdout_path) if File.exists?(stdout_path)
          File.delete(stderr_path) if File.exists?(stderr_path)
        end
      end

      private def self.run_hidden_status(command : String, args : Array(String),
                                         output : File, error : File) : Int32
        process_info = start_hidden(command, args, output, error)
        begin
          LibC.CloseHandle(process_info.hThread)
          process_info.hThread = Pointer(Void).null
          LibC.WaitForSingleObject(process_info.hProcess, LibC::INFINITE)
          unless LibC.GetExitCodeProcess(process_info.hProcess, out exit_code) != 0
            raise IO::Error.from_winerror("Could not read process exit code")
          end
          exit_code.to_i32
        ensure
          LibC.CloseHandle(process_info.hProcess) unless process_info.hProcess.null?
          LibC.CloseHandle(process_info.hThread) unless process_info.hThread.null?
        end
      end

      private def self.start_hidden(command : String, args : Array(String),
                                    output : File, error : File) : LibC::PROCESS_INFORMATION
        executable = which(command)
        raise IO::Error.new("executable not found") unless executable

        input = File.open("NUL", "r")
        inherited = [] of LibC::HANDLE
        process_info = LibC::PROCESS_INFORMATION.new
        begin
          startup_info = LibC::STARTUPINFOW.new
          startup_info.cb = sizeof(LibC::STARTUPINFOW)
          startup_info.dwFlags = LibC::STARTF_USESTDHANDLES
          startup_info.hStdInput = duplicate_inheritable(input, inherited)
          startup_info.hStdOutput = duplicate_inheritable(output, inherited)
          startup_info.hStdError = duplicate_inheritable(error, inherited)

          command_line = Process.quote_windows([executable] + args)
          created = LibC.CreateProcessW(
            Crystal::System.to_wstr(executable),
            Crystal::System.to_wstr(command_line),
            Pointer(LibC::SECURITY_ATTRIBUTES).null,
            Pointer(LibC::SECURITY_ATTRIBUTES).null,
            1,
            DETACHED_PROCESS,
            Pointer(Void).null,
            Pointer(UInt16).null,
            pointerof(startup_info),
            pointerof(process_info),
          )
          raise IO::Error.from_winerror("Error executing process") if created == 0

          process_info
        ensure
          input.close
          inherited.each { |handle| LibC.CloseHandle(handle) }
        end
      end

      private def self.duplicate_inheritable(file : File, handles : Array(LibC::HANDLE)) : LibC::HANDLE
        process = LibC.GetCurrentProcess
        source = LibC::HANDLE.new(file.fd)
        unless LibC.DuplicateHandle(
                 process,
                 source,
                 process,
                 out duplicate,
                 0,
                 1,
                 LibC::DUPLICATE_SAME_ACCESS,
               ) != 0
          raise IO::Error.from_winerror("Could not prepare process output")
        end
        handles << duplicate
        duplicate
      end
    {% end %}
  end
end
