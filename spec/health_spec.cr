require "./spec_helper"

describe Patty::Core::Health::Checker do
  it "reports disabled routes without probing them" do
    profile = Patty::Profile.new(
      caddy: "app.localhost {\n    reverse_proxy 127.0.0.1:1\n}\n",
      id: "app")

    check = Patty::Core::Health::Checker.check(profile, false, true)

    check.state.should eq Patty::Core::Health::State::Disabled
  end

  it "detects reachable and unavailable reverse proxy backends" do
    server = TCPServer.new("127.0.0.1", 0)
    port = server.local_address.as(Socket::IPAddress).port
    reachable = Patty::Profile.new(
      caddy: "app.localhost {\n    reverse_proxy 127.0.0.1:#{port}\n}\n",
      id: "reachable")

    good = Patty::Core::Health::Checker.check(reachable, true, true)
    server.close
    unavailable = reachable.dup
    unavailable.id = "unavailable"
    bad = Patty::Core::Health::Checker.check(unavailable, true, true)

    good.state.should eq Patty::Core::Health::State::Healthy
    bad.state.should eq Patty::Core::Health::State::Unhealthy
    bad.label.should eq "backend down"
  end

  it "checks file server roots" do
    root = File.join(Dir.tempdir, "patty-health-#{Random::Secure.hex(4)}")
    Dir.mkdir_p(root)
    profile = Patty::Profile.new(
      caddy: "files.localhost {\n    root * \"#{root}\"\n    file_server\n}\n",
      id: "files")

    check = Patty::Core::Health::Checker.check(profile, true, true)

    check.state.should eq Patty::Core::Health::State::Healthy
  ensure
    FileUtils.rm_rf(root) if root
  end
end
