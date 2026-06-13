require "./spec_helper"

private def jellyfin_profile : Patty::Profile
  Patty::Profile.new(
    caddy: "jellyfin.localhost {\n    reverse_proxy 127.0.0.1:8096\n}\n",
    program: "jellyfin",
    id: "jellyfin")
end

describe Patty::Caddy::DashboardAddress do
  it "accepts hostnames and http(s) URLs without paths" do
    Patty::Caddy::DashboardAddress.normalize("patty.example.com").should eq "patty.example.com"
    Patty::Caddy::DashboardAddress.normalize("https://patty.example.com/").should eq "https://patty.example.com"
    Patty::Caddy::DashboardAddress.browser_url("patty.example.com").should eq "https://patty.example.com"
  end

  it "rejects paths and Caddy syntax" do
    expect_raises(ArgumentError) do
      Patty::Caddy::DashboardAddress.normalize("https://patty.example.com/admin")
    end
    expect_raises(ArgumentError) do
      Patty::Caddy::DashboardAddress.normalize("patty.example.com {\nrespond ok\n}")
    end
  end

  it "rejects public plaintext HTTP but permits loopback HTTP" do
    expect_raises(ArgumentError, /requires HTTPS/) do
      Patty::Caddy::DashboardAddress.normalize("http://patty.example.com")
    end
    Patty::Caddy::DashboardAddress.normalize("http://localhost:7629")
      .should eq "http://localhost:7629"
  end
end

describe Patty::Caddy::DashboardRoute do
  it "does not render the public route before credentials exist" do
    fresh_home!
    config = Patty::Config.instance
    config.caddy.dashboard_address = "patty.example.com"

    Patty::Caddy::DashboardRoute.dashboard_snippet(config).should be_nil
  end

  it "reports and removes a stale dashboard snippet without credentials" do
    fresh_home!
    config = Patty::Config.instance
    config.caddy.dashboard_address = "patty.example.com"
    path = Patty::Caddy::Snippets.path_for(Patty::Caddy::DashboardRoute::ID)
    Patty::Caddy::Snippets.write(
      Patty::Caddy::DashboardRoute::ID,
      "patty.example.com {\n    reverse_proxy 127.0.0.1:7629\n}\n")

    Patty::Caddy::DashboardRoute.sync_file(config).should be_true
    File.exists?(path).should be_false
    Patty::Caddy::DashboardRoute.sync_file(config).should be_false
  end

  it "renders a reverse proxy to Patty and avoids profile ID collisions" do
    fresh_home!
    Patty::Auth.set_password("configured-password")
    config = Patty::Config.instance
    config.caddy.dashboard_address = "patty.example.com"
    config.server.bind = "0.0.0.0"
    config.server.port = 7629

    content = Patty::Caddy::DashboardRoute.dashboard_snippet(config).not_nil!

    Patty::Caddy::DashboardRoute::ID.should eq "__patty-dashboard"
    content.should contain "patty.example.com {"
    content.should contain "reverse_proxy 127.0.0.1:7629"
  end
end

describe Patty::Caddy::PortableBackend do
  it "bootstraps an active Caddyfile importing the enabled dir" do
    fresh_home!
    backend = Patty::Caddy::PortableBackend.new
    backend.bootstrap!
    content = File.read(backend.main_caddyfile)
    content.should contain %(import "#{backend.enabled_dir.gsub('\\', '/')}/*.caddy")
  end

  it "repairs a stale managed Caddyfile after the data directory moves" do
    fresh_home!
    backend = Patty::Caddy::PortableBackend.new
    File.write(backend.main_caddyfile, %(import "C:/old/patty/enabled/*.caddy"\n))

    backend.bootstrap!

    File.read(backend.main_caddyfile).should eq backend.caddyfile_content(backend.enabled_dir)
  end
end

describe Patty::Caddy::Snippets do
  it "writes and removes snippets" do
    fresh_home!
    profile = jellyfin_profile
    Patty::Caddy::Snippets.write("jellyfin", Patty::Caddy::Snippets.render(profile))
    Patty::Caddy::Snippets.enabled?("jellyfin").should be_true
    File.read(Patty::Caddy::Snippets.path_for("jellyfin")).should contain "reverse_proxy"
    Patty::Caddy::Snippets.files.should eq [Patty::Caddy::Snippets.path_for("jellyfin")]

    Patty::Caddy::Snippets.remove("jellyfin")
    Patty::Caddy::Snippets.enabled?("jellyfin").should be_false
  end
end

describe Patty::Caddy::Manager do
  it "enables and removes the managed dashboard route" do
    fresh_home!
    Patty::Auth.set_password("configured-password")
    Patty::Caddy.runtime = FakeCaddyRuntime.new
    config = Patty::Config.instance
    config.caddy.dashboard_address = "patty.example.com"

    enabled = Patty::Caddy::Manager.configure_dashboard(config)

    enabled.ok?.should be_true
    path = Patty::Caddy::Snippets.path_for(Patty::Caddy::DashboardRoute::ID)
    File.read(path).should contain "reverse_proxy 127.0.0.1:7629"

    config.caddy.dashboard_address = nil
    disabled = Patty::Caddy::Manager.configure_dashboard(config)

    disabled.ok?.should be_true
    File.exists?(path).should be_false
  end

  it "starts Caddy when applying while the admin API is not running" do
    fresh_home!
    runtime = FakeCaddyRuntime.new
    runtime.running = false
    Patty::Caddy.runtime = runtime

    result = Patty::Caddy::Manager.enable_route(jellyfin_profile)

    result.ok?.should be_true
    result.message.should contain "Caddy started."
    runtime.start_calls.should eq [Patty::Caddy::Manager.backend.main_caddyfile]
    runtime.reload_calls.should be_empty
  end

  it "reloads Caddy when it is already running" do
    fresh_home!
    runtime = FakeCaddyRuntime.new
    Patty::Caddy.runtime = runtime

    Patty::Caddy::Manager.reload_active.ok?.should be_true

    runtime.start_calls.should be_empty
    runtime.reload_calls.should eq [Patty::Caddy::Manager.backend.main_caddyfile]
  end

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
    bad = Patty::Profile.new(
      caddy: "broken.localhost {\n    reverse_proxie 127.0.0.1:1\n}\n",
      program: "broken",
      id: "broken")
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
