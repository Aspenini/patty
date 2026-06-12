module Patty::Core
  # Status snapshot used by the dashboard and GET /api/status.
  module State
    record ProfileStatus,
      id : String,
      program : String?,
      service : Services::Status?,
      adapter : String?,
      route_enabled : Bool,
      open_url : String?,
      health : Health::Check,
      warnings : Array(String)

    record Snapshot,
      caddy_found : Bool,
      caddy_running : Bool,
      profiles : Array(ProfileStatus)

    def self.snapshot : Snapshot
      caddy_found = Caddy::Validator.found?
      caddy_running = Caddy::Reloader.running?
      profiles = Profiles::Store.all.map do |profile|
        profile_status(profile, caddy_running)
      end
      Snapshot.new(
        caddy_found: caddy_found,
        caddy_running: caddy_running,
        profiles: profiles,
      )
    end

    def self.profile_status(profile : Profile, caddy_running = Caddy::Reloader.running?) : ProfileStatus
      status, adapter =
        if program = profile.program
          Services::Manager.status(program)
        else
          {nil, nil}
        end
      route_enabled = Caddy::Snippets.enabled?(profile.slug)
      ProfileStatus.new(
        id: profile.slug,
        program: profile.program,
        service: status,
        adapter: adapter,
        route_enabled: route_enabled,
        open_url: profile.open_url,
        health: Health::Checker.check(profile, route_enabled, caddy_running),
        warnings: Profiles::Warnings.for(profile),
      )
    end
  end
end
