require "./spec_helper"

private def jellyfin_profile : Patty::Profile
  Patty::Profile.new(1, "Jellyfin", "jellyfin",
    "jellyfin.localhost {\n    reverse_proxy 127.0.0.1:8096\n}\n")
end

private def caddy_available? : Bool
  Patty::Caddy::Validator.found?
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
    pending! "caddy binary not installed" unless caddy_available?
    fresh_home!
    result = Patty::Caddy::Manager.enable_route(jellyfin_profile)
    # Reload may fail (no caddy running in specs) but the snippet must apply.
    Patty::Caddy::Snippets.enabled?("jellyfin").should be_true
    result.message.should contain "Enabled Caddy route jellyfin.caddy."
    Dir.children(Patty::Util::Paths.backups_dir).size.should be >= 1
  end

  it "refuses to enable an invalid snippet" do
    pending! "caddy binary not installed" unless caddy_available?
    fresh_home!
    bad = Patty::Profile.new(1, "Broken", "broken",
      "broken.localhost {\n    reverse_proxie 127.0.0.1:1\n}\n")
    result = Patty::Caddy::Manager.enable_route(bad)
    result.ok?.should be_false
    Patty::Caddy::Snippets.enabled?("broken").should be_false
  end

  it "disables routes" do
    pending! "caddy binary not installed" unless caddy_available?
    fresh_home!
    Patty::Caddy::Manager.enable_route(jellyfin_profile)
    result = Patty::Caddy::Manager.disable_route("jellyfin")
    Patty::Caddy::Snippets.enabled?("jellyfin").should be_false
    result.message.should contain "Disabled Caddy route jellyfin.caddy."
  end

  it "validates the active config" do
    pending! "caddy binary not installed" unless caddy_available?
    fresh_home!
    Patty::Caddy::Validator.validate_active.ok?.should be_true
  end
end
