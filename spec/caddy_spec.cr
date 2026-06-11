require "./spec_helper"

private def jellyfin_profile : Patty::Profile
  Patty::Profile.new(1, "Jellyfin", "jellyfin",
    "jellyfin.localhost {\n    reverse_proxy 127.0.0.1:8096\n}\n")
end

describe Patty::Caddy::PortableBackend do
  it "bootstraps an active Caddyfile importing the enabled dir" do
    fresh_home!
    backend = Patty::Caddy::PortableBackend.new
    backend.bootstrap!
    content = File.read(backend.main_caddyfile)
    content.should contain %(import "#{backend.enabled_dir}/*.caddy")
  end
end

describe Patty::Caddy::Snippets do
  it "writes and removes snippets" do
    fresh_home!
    profile = jellyfin_profile
    Patty::Caddy::Snippets.write("jellyfin", Patty::Caddy::Snippets.render(profile))
    Patty::Caddy::Snippets.enabled?("jellyfin").should be_true
    File.read(Patty::Caddy::Snippets.path_for("jellyfin")).should contain "reverse_proxy"

    Patty::Caddy::Snippets.remove("jellyfin")
    Patty::Caddy::Snippets.enabled?("jellyfin").should be_false
  end
end

describe Patty::Caddy::Manager do
  it "enables a valid route and backs up prior state" do
    fresh_home!
    Patty::Caddy.runtime = FakeCaddyRuntime.new
    result = Patty::Caddy::Manager.enable_route(jellyfin_profile)
    result.ok?.should be_true
    Patty::Caddy::Snippets.enabled?("jellyfin").should be_true
    result.message.should contain "Enabled Caddy route jellyfin.caddy."
    Dir.children(Patty::Util::Paths.backups_dir).size.should be >= 1
  end

  it "refuses to enable an invalid snippet" do
    fresh_home!
    runtime = FakeCaddyRuntime.new
    runtime.validate_results << Patty::Result.failure("Caddy validation failed.", "bad directive")
    Patty::Caddy.runtime = runtime
    bad = Patty::Profile.new(1, "Broken", "broken",
      "broken.localhost {\n    reverse_proxie 127.0.0.1:1\n}\n")
    result = Patty::Caddy::Manager.enable_route(bad)
    result.ok?.should be_false
    Patty::Caddy::Snippets.enabled?("broken").should be_false
  end

  it "disables routes" do
    fresh_home!
    Patty::Caddy.runtime = FakeCaddyRuntime.new
    Patty::Caddy::Manager.enable_route(jellyfin_profile)
    result = Patty::Caddy::Manager.disable_route("jellyfin")
    Patty::Caddy::Snippets.enabled?("jellyfin").should be_false
    result.message.should contain "Disabled Caddy route jellyfin.caddy."
  end

  it "validates the active config" do
    fresh_home!
    Patty::Caddy.runtime = FakeCaddyRuntime.new
    Patty::Caddy::Validator.validate_active.ok?.should be_true
  end

  it "restores exact prior snippet bytes when reload fails" do
    fresh_home!
    original = "# exact original\njellyfin.localhost { respond \"old\" }\n"
    Patty::Caddy::Snippets.write("jellyfin", original)
    runtime = FakeCaddyRuntime.new
    runtime.reload_results = [
      Patty::Result.failure("reload failed", "new config rejected"),
      Patty::Result.success("rollback reload succeeded"),
    ]
    Patty::Caddy.runtime = runtime

    result = Patty::Caddy::Manager.enable_route(jellyfin_profile)

    result.ok?.should be_false
    result.message.should contain "previous route state was restored"
    File.read(Patty::Caddy::Snippets.path_for("jellyfin")).should eq original
    runtime.reload_calls.size.should eq 2
  end

  it "reports when rollback reload also fails" do
    fresh_home!
    original = "# original\njellyfin.localhost { respond \"old\" }\n"
    Patty::Caddy::Snippets.write("jellyfin", original)
    runtime = FakeCaddyRuntime.new
    runtime.reload_results = [
      Patty::Result.failure("reload failed", "new config rejected"),
      Patty::Result.failure("rollback failed", "admin API unavailable"),
    ]
    Patty::Caddy.runtime = runtime

    result = Patty::Caddy::Manager.enable_route(jellyfin_profile)

    result.ok?.should be_false
    result.message.should contain "rollback reload also failed"
    result.detail.to_s.should contain "admin API unavailable"
    File.read(Patty::Caddy::Snippets.path_for("jellyfin")).should eq original
  end

  it "removes a newly-created snippet when reload fails" do
    fresh_home!
    runtime = FakeCaddyRuntime.new
    runtime.reload_results = [
      Patty::Result.failure("reload failed"),
      Patty::Result.success("rollback reload succeeded"),
    ]
    Patty::Caddy.runtime = runtime

    Patty::Caddy::Manager.enable_route(jellyfin_profile).ok?.should be_false
    Patty::Caddy::Snippets.enabled?("jellyfin").should be_false
  end
end
