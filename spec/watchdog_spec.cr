require "./spec_helper"

describe Patty::Core::Watchdog do
  it "does nothing when no routes are enabled" do
    fresh_home!
    runtime = FakeCaddyRuntime.new
    runtime.running = false
    Patty::Caddy.runtime = runtime

    Patty::Core::Watchdog.check_once.should be_nil
    runtime.start_calls.should be_empty
  end

  it "restarts Caddy when an enabled route exists" do
    fresh_home!
    profile = Patty::Profiles::Store.save(Patty::Profile.new(
      caddy: "app.localhost {\n    respond \"ok\"\n}\n",
      id: "app"))
    Patty::Caddy::Snippets.write(profile.slug, Patty::Caddy::Snippets.render(profile))
    runtime = FakeCaddyRuntime.new
    runtime.running = false
    Patty::Caddy.runtime = runtime

    result = Patty::Core::Watchdog.check_once

    result.should_not be_nil
    result.not_nil!.ok?.should be_true
    runtime.start_calls.should_not be_empty
  end
end
