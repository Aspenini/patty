require "./spec_helper"

private def action_profile : Patty::Profile
  Patty::Profile.new(
    1,
    "Action App",
    "action-app",
    "action.localhost {\n    reverse_proxy 127.0.0.1:4321\n}\n",
    id: "action-app")
end

private def save_action_profile : Patty::Profile
  Patty::Profiles::Store.save(action_profile)
end

describe Patty::Core::Actions do
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
      1,
      "Edited App",
      original.program,
      "edited.localhost {\n    respond \"new\"\n}\n",
      id: original.slug)

    result = Patty::Core::Actions.update_profile(original.slug, edited)

    result.ok?.should be_false
    Patty::Profiles::Store.find(original.slug).not_nil!.name.should eq original.name
    File.read(Patty::Caddy::Snippets.path_for(original.slug)).should eq original_snippet
  end

  it "restores an enabled route when profile persistence fails" do
    fresh_home!
    original = save_action_profile
    original_snippet = Patty::Caddy::Snippets.render(original)
    Patty::Caddy::Snippets.write(original.slug, original_snippet)
    Patty::Caddy.runtime = FakeCaddyRuntime.new
    edited = Patty::Profile.new(
      1,
      "Edited App",
      original.program,
      "edited.localhost {\n    respond \"new\"\n}\n",
      id: original.slug)

    File.chmod(Patty::Util::Paths.profiles_dir, 0o555)
    begin
      result = Patty::Core::Actions.update_profile(original.slug, edited)
    ensure
      File.chmod(Patty::Util::Paths.profiles_dir, 0o755)
    end

    result.ok?.should be_false
    Patty::Profiles::Store.find(original.slug).not_nil!.name.should eq original.name
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

    File.chmod(Patty::Util::Paths.profiles_dir, 0o555)
    begin
      result = Patty::Core::Actions.delete_profile(profile.slug)
    ensure
      File.chmod(Patty::Util::Paths.profiles_dir, 0o755)
    end

    result.ok?.should be_false
    Patty::Profiles::Store.exists?(profile.slug).should be_true
    File.read(Patty::Caddy::Snippets.path_for(profile.slug)).should eq original_snippet
  end
end
