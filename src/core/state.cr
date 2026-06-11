module Patty::Core
  # Status snapshot used by the dashboard and GET /api/status.
  module State
    record ProfileStatus,
      id : String,
      name : String,
      program : String,
      service : Services::Status,
      adapter : String?,
      route_enabled : Bool,
      open_url : String?,
      description : String?

    record Snapshot,
      caddy_found : Bool,
      caddy_running : Bool,
      profiles : Array(ProfileStatus)

    def self.snapshot : Snapshot
      profiles = Profiles::Store.all.map do |profile|
        status, adapter = Services::Manager.status(profile.program)
        ProfileStatus.new(
          id: profile.slug,
          name: profile.name,
          program: profile.program,
          service: status,
          adapter: adapter,
          route_enabled: Caddy::Snippets.enabled?(profile.slug),
          open_url: profile.open_url,
          description: profile.description,
        )
      end
      Snapshot.new(
        caddy_found: Caddy::Validator.found?,
        caddy_running: Caddy::Reloader.running?,
        profiles: profiles,
      )
    end
  end
end
