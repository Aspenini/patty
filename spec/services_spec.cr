require "./spec_helper"

class FakeWindowsServiceAdapter < Patty::Services::WindowsServiceAdapter
  getter calls = [] of Array(String)
  property responses = [] of Patty::Util::CommandResult

  protected def execute(command : String, args : Array(String)) : Patty::Util::CommandResult
    @calls << [command] + args
    @responses.shift? || Patty::Util::CommandResult.new(0, "STATE : 4 RUNNING", "")
  end

  protected def pause
  end
end

class FakeLinuxSystemdAdapter < Patty::Services::LinuxSystemdAdapter
  getter calls = [] of Array(String)
  property responses = [] of Patty::Util::CommandResult

  protected def execute(command : String, args : Array(String)) : Patty::Util::CommandResult
    @calls << [command] + args
    @responses.shift? || Patty::Util::CommandResult.new(0, "", "")
  end
end

describe Patty::Services::WindowsServiceAdapter do
  it "detects and reports Windows service state" do
    adapter = FakeWindowsServiceAdapter.new
    adapter.responses = [
      Patty::Util::CommandResult.new(0, "STATE : 4 RUNNING", ""),
      Patty::Util::CommandResult.new(0, "STATE : 1 STOPPED", ""),
      Patty::Util::CommandResult.new(1060, "", "service does not exist"),
    ]

    adapter.status("JellyfinServer").should eq(Patty::Services::Status::Running)
    adapter.status("JellyfinServer").should eq(Patty::Services::Status::Stopped)
    adapter.status("missing").should eq(Patty::Services::Status::NotFound)
  end

  it "starts a stopped Windows service and waits for running" do
    adapter = FakeWindowsServiceAdapter.new
    adapter.responses = [
      Patty::Util::CommandResult.new(0, "STATE : 1 STOPPED", ""),
      Patty::Util::CommandResult.new(0, "START_PENDING", ""),
      Patty::Util::CommandResult.new(0, "STATE : 4 RUNNING", ""),
    ]

    adapter.start("JellyfinServer").ok?.should be_true
    adapter.calls.should contain(["sc.exe", "start", "JellyfinServer"])
  end
end

describe Patty::Services::LinuxSystemdAdapter do
  it "normalizes unit names and reports active services" do
    adapter = FakeLinuxSystemdAdapter.new
    adapter.responses = [
      Patty::Util::CommandResult.new(0, "loaded\n", ""),
      Patty::Util::CommandResult.new(0, "active\n", ""),
    ]

    adapter.status("jellyfin").should eq(Patty::Services::Status::Running)
    adapter.calls.should contain(["systemctl", "show", "jellyfin.service", "--property=LoadState", "--value"])
  end

  it "runs systemctl without a shell" do
    adapter = FakeLinuxSystemdAdapter.new
    adapter.responses = [Patty::Util::CommandResult.new(0, "", "")]

    adapter.restart("jellyfin.service").ok?.should be_true
    adapter.calls.should eq([["systemctl", "restart", "jellyfin.service"]])
  end
end
