require "./spec_helper"

describe Patty::Install::Autostart do
  it "builds a current-user Windows startup registry command" do
    args = Patty::Install::Autostart.windows_registry_args("C:\\Program Files\\Patty\\patty.exe")

    args.should contain("ADD")
    args.should contain("HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run")
    args.should contain("Patty")
    args.should contain("\"C:\\Program Files\\Patty\\patty.exe\" run")
  end

  it "uses the background launcher when the GUI executable is active" do
    args = Patty::Install::Autostart.windows_registry_args("C:\\Program Files\\Patty\\pattyw.exe")

    args.should contain("\"C:\\Program Files\\Patty\\pattyw.exe\"")
    args.should_not contain("\"C:\\Program Files\\Patty\\pattyw.exe\" run")
  end

  it "renders a macOS LaunchAgent without unescaped paths" do
    plist = Patty::Install::Autostart.macos_plist("/Applications/Patty & Caddy/patty")

    plist.should contain("org.patty.app")
    plist.should contain("/Applications/Patty &amp; Caddy/patty")
    plist.should contain("<string>run</string>")
  end

  it "renders a user systemd unit with a quoted executable" do
    unit = Patty::Install::Autostart.linux_unit("/home/alice/My Apps/patty")

    unit.should contain("ExecStart=\"/home/alice/My Apps/patty\" run")
    unit.should contain("WantedBy=default.target")
  end
end
