module Patty::Install::Autostart
  WINDOWS_RUN_KEY   = %q(HKCU\Software\Microsoft\Windows\CurrentVersion\Run)
  WINDOWS_RUN_VALUE = "Patty"
  WINDOWS_TASK      = "Patty"
  MAC_LABEL         = "org.patty.app"
  LINUX_UNIT        = "patty.service"

  def self.install : Result
    executable = Process.executable_path
    return Result.failure("Could not determine the Patty executable path.") unless executable

    result =
      if Util::Platform.windows?
        install_windows(executable)
      elsif Util::Platform.macos?
        install_macos(executable)
      elsif Util::Platform.linux?
        install_linux(executable)
      else
        Result.failure("Automatic startup is not supported on #{Util::Platform.name}.")
      end

    Util::ActionLog.log(result.message)
    result
  end

  def self.uninstall : Result
    result =
      if Util::Platform.windows?
        uninstall_windows
      elsif Util::Platform.macos?
        uninstall_macos
      elsif Util::Platform.linux?
        uninstall_linux
      else
        Result.failure("Automatic startup is not supported on #{Util::Platform.name}.")
      end

    Util::ActionLog.log(result.message)
    result
  end

  def self.installed? : Bool
    if Util::Platform.windows?
      windows_registry_installed? || windows_task_installed?
    elsif Util::Platform.macos?
      File.exists?(mac_plist_path)
    elsif Util::Platform.linux?
      File.exists?(linux_unit_path)
    else
      false
    end
  end

  def self.windows_registry_args(executable : String) : Array(String)
    launcher, arguments = windows_launcher(executable)
    command = %("#{launcher}")
    command += " #{arguments}" unless arguments.empty?
    ["ADD", WINDOWS_RUN_KEY, "/v", WINDOWS_RUN_VALUE, "/t", "REG_SZ", "/d", command, "/f"]
  end

  def self.macos_plist(executable : String) : String
    escaped_executable = xml_escape(executable)
    escaped_log = xml_escape(Util::Paths.log_file)
    <<-XML
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>Label</key>
      <string>#{MAC_LABEL}</string>
      <key>ProgramArguments</key>
      <array>
        <string>#{escaped_executable}</string>
        <string>run</string>
      </array>
      <key>RunAtLoad</key>
      <true/>
      <key>KeepAlive</key>
      <true/>
      <key>StandardOutPath</key>
      <string>#{escaped_log}</string>
      <key>StandardErrorPath</key>
      <string>#{escaped_log}</string>
    </dict>
    </plist>
    XML
  end

  def self.linux_unit(executable : String) : String
    <<-UNIT
    [Unit]
    Description=Patty Caddy profile manager
    After=network-online.target
    Wants=network-online.target

    [Service]
    Type=simple
    ExecStart=#{systemd_quote(executable)} run
    Restart=on-failure
    RestartSec=3

    [Install]
    WantedBy=default.target
    UNIT
  end

  private def self.install_windows(executable : String) : Result
    result = run_result(
      Util::ProcessRunner.run("reg.exe", windows_registry_args(executable)),
      "Patty will start automatically when you sign in.",
      "Could not install Patty automatic startup."
    )
    remove_windows_task if result.ok?
    result
  end

  private def self.uninstall_windows : Result
    details = [] of String

    if windows_registry_installed?
      command = Util::ProcessRunner.run(
        "reg.exe",
        ["DELETE", WINDOWS_RUN_KEY, "/v", WINDOWS_RUN_VALUE, "/f"])
      details << command.output unless command.success?
    end

    if windows_task_installed?
      command = remove_windows_task
      details << command.output unless command.success?
    end

    if details.empty?
      Result.success("Patty automatic startup removed.")
    else
      Result.failure("Could not remove Patty automatic startup.", details.reject(&.empty?).join('\n'))
    end
  end

  private def self.windows_registry_installed? : Bool
    Util::ProcessRunner.run(
      "reg.exe",
      ["QUERY", WINDOWS_RUN_KEY, "/v", WINDOWS_RUN_VALUE]).success?
  end

  private def self.windows_task_installed? : Bool
    Util::ProcessRunner.run("schtasks.exe", ["/Query", "/TN", WINDOWS_TASK]).success?
  end

  private def self.remove_windows_task : Util::CommandResult
    Util::ProcessRunner.run("schtasks.exe", ["/Delete", "/TN", WINDOWS_TASK, "/F"])
  end

  private def self.windows_launcher(executable : String) : {String, String}
    if executable.gsub('\\', '/').split('/').last.downcase == "pattyw.exe"
      {executable, ""}
    else
      background = File.join(File.dirname(executable), "pattyw.exe")
      File.exists?(background) ? {background, ""} : {executable, "run"}
    end
  end

  private def self.install_macos(executable : String) : Result
    path = mac_plist_path
    Dir.mkdir_p(File.dirname(path))
    Util::AtomicFile.write(path, macos_plist(executable))
    Util::ProcessRunner.run("launchctl", ["unload", path]) if installed?
    run_result(
      Util::ProcessRunner.run("launchctl", ["load", "-w", path]),
      "Patty will start automatically when you sign in.",
      "The LaunchAgent was written, but launchctl could not load it."
    )
  rescue ex
    Result.failure("Could not install Patty automatic startup.", ex.message)
  end

  private def self.uninstall_macos : Result
    path = mac_plist_path
    Util::ProcessRunner.run("launchctl", ["unload", "-w", path]) if File.exists?(path)
    File.delete(path) if File.exists?(path)
    Result.success("Patty automatic startup removed.")
  rescue ex
    Result.failure("Could not remove Patty automatic startup.", ex.message)
  end

  private def self.install_linux(executable : String) : Result
    path = linux_unit_path
    Dir.mkdir_p(File.dirname(path))
    Util::AtomicFile.write(path, linux_unit(executable))
    reload = Util::ProcessRunner.run("systemctl", ["--user", "daemon-reload"])
    return Result.failure("The systemd unit was written, but systemd could not reload.", reload.output) unless reload.success?
    run_result(
      Util::ProcessRunner.run("systemctl", ["--user", "enable", "--now", LINUX_UNIT]),
      "Patty will start automatically when you sign in.",
      "The systemd unit was written, but systemd could not enable it."
    )
  rescue ex
    Result.failure("Could not install Patty automatic startup.", ex.message)
  end

  private def self.uninstall_linux : Result
    Util::ProcessRunner.run("systemctl", ["--user", "disable", "--now", LINUX_UNIT])
    path = linux_unit_path
    File.delete(path) if File.exists?(path)
    Util::ProcessRunner.run("systemctl", ["--user", "daemon-reload"])
    Result.success("Patty automatic startup removed.")
  rescue ex
    Result.failure("Could not remove Patty automatic startup.", ex.message)
  end

  private def self.mac_plist_path : String
    File.join(Path.home.to_s, "Library", "LaunchAgents", "#{MAC_LABEL}.plist")
  end

  private def self.linux_unit_path : String
    File.join(ENV["XDG_CONFIG_HOME"]? || File.join(Path.home.to_s, ".config"), "systemd", "user", LINUX_UNIT)
  end

  private def self.run_result(command : Util::CommandResult, success : String, failure : String) : Result
    command.success? ? Result.success(success) : Result.failure(failure, command.output)
  end

  private def self.xml_escape(value : String) : String
    value.gsub('&', "&amp;").gsub('<', "&lt;").gsub('>', "&gt;").gsub('"', "&quot;").gsub('\'', "&apos;")
  end

  private def self.systemd_quote(value : String) : String
    %("#{value.gsub("\\", "\\\\").gsub("\"", "\\\"").gsub("%", "%%")}")
  end
end
