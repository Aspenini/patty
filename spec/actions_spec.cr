require "./spec_helper"

private def action_profile : Patty::Profile
  Patty::Profile.new(
    caddy: "action.localhost {\n    reverse_proxy 127.0.0.1:4321\n}\n",
    program: "action-app",
    id: "action-app")
end

private def caddy_only_profile : Patty::Profile
  Patty::Profile.new(
    caddy: "files.localhost {\n    root * /srv/files\n    file_server\n}\n",
    id: "static-files")
end

private def save_action_profile : Patty::Profile
  Patty::Profiles::Store.save(action_profile)
end

private def with_profile_mutation_blocked(path : String, & : -> Patty::Result) : Patty::Result
  {% if flag?(:windows) %}
    handle = LibC.CreateFileW(
      Crystal::System.to_wstr(path),
      LibC::GENERIC_READ,
      LibC::FILE_SHARE_READ | LibC::FILE_SHARE_WRITE,
      nil,
      LibC::OPEN_EXISTING,
      LibC::FILE_ATTRIBUTE_NORMAL,
      LibC::HANDLE.null)
    raise "could not lock test profile" if handle == LibC::INVALID_HANDLE_VALUE
    begin
      yield
    ensure
      LibC.CloseHandle(handle)
    end
  {% else %}
    dir = File.dirname(path)
    File.chmod(dir, 0o555)
    begin
      yield
    ensure
      File.chmod(dir, 0o755)
    end
  {% end %}
end

describe Patty::Core::Actions do
  it "starts and stops Caddy-only profiles without invoking service adapters" do
    fresh_home!
    profile = Patty::Profiles::Store.save(caddy_only_profile)
    service = FakeServiceAdapter.new(Patty::Services::Status::Stopped)
    Patty::Services::Manager.adapters = [service] of Patty::Services::Adapter
    Patty::Caddy.runtime = FakeCaddyRuntime.new

    Patty::Core::Actions.start_profile(profile.slug).ok?.should be_true
    Patty::Caddy::Snippets.enabled?(profile.slug).should be_true

    Patty::Core::Actions.stop_profile(profile.slug).ok?.should be_true
    Patty::Caddy::Snippets.enabled?(profile.slug).should be_false
    service.actions.should be_empty
  end

  it "refuses to restart a Caddy-only profile without invoking service adapters" do
    fresh_home!
    profile = Patty::Profiles::Store.save(caddy_only_profile)
    service = FakeServiceAdapter.new(Patty::Services::Status::Stopped)
    Patty::Services::Manager.adapters = [service] of Patty::Services::Adapter

    result = Patty::Core::Actions.restart_profile(profile.slug)

    result.ok?.should be_false
    result.message.should contain "no program"
    service.actions.should be_empty
  end

  it "stops a newly-started service when route enable fails" do
    fresh_home!
    profile = save_action_profile
    service = FakeServiceAdapter.new(Patty::Services::Status::Stopped)
    Patty::Services::Manager.adapters = [service] of Patty::Services::Adapter
    runtime = FakeCaddyRuntime.new
    runtime.validate_results << Patty::Result.failure("validation failed", "bad route")
    Patty::Caddy.runtime = runtime

    result = Patty::Core::Actions.start_profile(profile.slug)

    result.ok?.should be_false
    result.message.should contain "restored to stopped"
    service.actions.should eq ["start", "stop"]
    service.current_status.should eq Patty::Services::Status::Stopped
  end

  it "restarts a stopped service when route disable fails" do
    fresh_home!
    profile = save_action_profile
    Patty::Caddy::Snippets.write(profile.slug, Patty::Caddy::Snippets.render(profile))
    service = FakeServiceAdapter.new(Patty::Services::Status::Running)
    Patty::Services::Manager.adapters = [service] of Patty::Services::Adapter
    runtime = FakeCaddyRuntime.new
    runtime.validate_results << Patty::Result.failure("validation failed", "dependency still uses route")
    Patty::Caddy.runtime = runtime

    result = Patty::Core::Actions.stop_profile(profile.slug)

    result.ok?.should be_false
    result.message.should contain "restored to running"
    service.actions.should eq ["stop", "start"]
    service.current_status.should eq Patty::Services::Status::Running
  end

  it "does not compensate a service whose prior state was unknown" do
    fresh_home!
    profile = save_action_profile
    service = FakeServiceAdapter.new(Patty::Services::Status::Unknown)
    Patty::Services::Manager.adapters = [service] of Patty::Services::Adapter
    runtime = FakeCaddyRuntime.new
    runtime.validate_results << Patty::Result.failure("validation failed")
    Patty::Caddy.runtime = runtime

    result = Patty::Core::Actions.start_profile(profile.slug)

    result.ok?.should be_false
    result.detail.to_s.should contain "compensation skipped"
    service.actions.should eq ["start"]
  end

  it "does not stop a service that was already running before a failed start action" do
    fresh_home!
    profile = save_action_profile
    service = FakeServiceAdapter.new(Patty::Services::Status::Running)
    Patty::Services::Manager.adapters = [service] of Patty::Services::Adapter
    runtime = FakeCaddyRuntime.new
    runtime.validate_results << Patty::Result.failure("validation failed")
    Patty::Caddy.runtime = runtime

    result = Patty::Core::Actions.start_profile(profile.slug)

    result.ok?.should be_false
    result.detail.to_s.should contain "prior state was running"
    service.actions.should eq ["start"]
  end

  it "does not start a service that was already stopped before a failed stop action" do
    fresh_home!
    profile = save_action_profile
    Patty::Caddy::Snippets.write(profile.slug, Patty::Caddy::Snippets.render(profile))
    service = FakeServiceAdapter.new(Patty::Services::Status::Stopped)
    Patty::Services::Manager.adapters = [service] of Patty::Services::Adapter
    runtime = FakeCaddyRuntime.new
    runtime.validate_results << Patty::Result.failure("validation failed")
    Patty::Caddy.runtime = runtime

    result = Patty::Core::Actions.stop_profile(profile.slug)

    result.ok?.should be_false
    result.detail.to_s.should contain "prior state was stopped"
    service.actions.should eq ["stop"]
  end

  it "reports a failed service compensation" do
    fresh_home!
    profile = save_action_profile
    service = FakeServiceAdapter.new(Patty::Services::Status::Stopped)
    service.stop_results << Patty::Result.failure("stop rollback failed", "brew error")
    Patty::Services::Manager.adapters = [service] of Patty::Services::Adapter
    runtime = FakeCaddyRuntime.new
    runtime.validate_results << Patty::Result.failure("validation failed")
    Patty::Caddy.runtime = runtime

    result = Patty::Core::Actions.start_profile(profile.slug)

    result.ok?.should be_false
    result.message.should contain "restoring the service also failed"
    result.detail.to_s.should contain "brew error"
  end

  it "reports a failed stop compensation" do
    fresh_home!
    profile = save_action_profile
    Patty::Caddy::Snippets.write(profile.slug, Patty::Caddy::Snippets.render(profile))
    service = FakeServiceAdapter.new(Patty::Services::Status::Running)
    service.start_results << Patty::Result.failure("start rollback failed", "brew error")
    Patty::Services::Manager.adapters = [service] of Patty::Services::Adapter
    runtime = FakeCaddyRuntime.new
    runtime.validate_results << Patty::Result.failure("validation failed")
    Patty::Caddy.runtime = runtime

    result = Patty::Core::Actions.stop_profile(profile.slug)

    result.ok?.should be_false
    result.message.should contain "restoring the service also failed"
    result.detail.to_s.should contain "brew error"
  end

  it "keeps the stored profile and route unchanged when an enabled edit fails" do
    fresh_home!
    original = save_action_profile
    original_snippet = Patty::Caddy::Snippets.render(original)
    Patty::Caddy::Snippets.write(original.slug, original_snippet)
    runtime = FakeCaddyRuntime.new
    runtime.validate_results << Patty::Result.failure("validation failed", "new snippet invalid")
    Patty::Caddy.runtime = runtime
    edited = Patty::Profile.new(
      caddy: "edited.localhost {\n    respond \"new\"\n}\n",
      program: original.program,
      id: original.slug)

    result = Patty::Core::Actions.update_profile(original.slug, edited)

    result.ok?.should be_false
    Patty::Profiles::Store.find(original.slug).not_nil!.caddy.should eq original.caddy
    File.read(Patty::Caddy::Snippets.path_for(original.slug)).should eq original_snippet
  end

  it "restores an enabled route when profile persistence fails" do
    fresh_home!
    original = save_action_profile
    original_snippet = Patty::Caddy::Snippets.render(original)
    Patty::Caddy::Snippets.write(original.slug, original_snippet)
    Patty::Caddy.runtime = FakeCaddyRuntime.new
    edited = Patty::Profile.new(
      caddy: "edited.localhost {\n    respond \"new\"\n}\n",
      program: original.program,
      id: original.slug)

    result = with_profile_mutation_blocked(Patty::Profiles::Store.path_for(original.slug)) do
      Patty::Core::Actions.update_profile(original.slug, edited)
    end

    result.ok?.should be_false
    Patty::Profiles::Store.find(original.slug).not_nil!.caddy.should eq original.caddy
    File.read(Patty::Caddy::Snippets.path_for(original.slug)).should eq original_snippet
  end

  it "does not delete a profile when its enabled route cannot be disabled" do
    fresh_home!
    profile = save_action_profile
    original_snippet = Patty::Caddy::Snippets.render(profile)
    Patty::Caddy::Snippets.write(profile.slug, original_snippet)
    runtime = FakeCaddyRuntime.new
    runtime.validate_results << Patty::Result.failure("validation failed")
    Patty::Caddy.runtime = runtime

    result = Patty::Core::Actions.delete_profile(profile.slug)

    result.ok?.should be_false
    Patty::Profiles::Store.exists?(profile.slug).should be_true
    File.read(Patty::Caddy::Snippets.path_for(profile.slug)).should eq original_snippet
  end

  it "re-enables the original route when profile deletion fails" do
    fresh_home!
    profile = save_action_profile
    original_snippet = Patty::Caddy::Snippets.render(profile)
    Patty::Caddy::Snippets.write(profile.slug, original_snippet)
    Patty::Caddy.runtime = FakeCaddyRuntime.new

    result = with_profile_mutation_blocked(Patty::Profiles::Store.path_for(profile.slug)) do
      Patty::Core::Actions.delete_profile(profile.slug)
    end

    result.ok?.should be_false
    Patty::Profiles::Store.exists?(profile.slug).should be_true
    File.read(Patty::Caddy::Snippets.path_for(profile.slug)).should eq original_snippet
  end
end
