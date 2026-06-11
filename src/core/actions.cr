module Patty::Core
  # The single choke point for everything the web UI (and any future CLI
  # command) can do. Every action logs what it did (spec §11).
  module Actions
    def self.start_profile(id : String) : Result
      profile = Profiles::Store.find(id)
      return not_found(id) unless profile

      service = Services::Manager.start(profile.program)
      unless service.ok?
        Util::ActionLog.log("Failed to start #{profile.program}: #{service.message}")
        return service
      end
      Util::ActionLog.log("Started #{profile.program}.")

      route = Caddy::Manager.enable_route(profile)
      Util::ActionLog.log(route.message)
      if route.ok?
        Result.success("Started #{profile.name} and enabled its route.")
      else
        Result.failure("#{profile.name} started, but its route was not fully enabled: #{route.message}",
          route.detail)
      end
    end

    def self.stop_profile(id : String) : Result
      profile = Profiles::Store.find(id)
      return not_found(id) unless profile

      service = Services::Manager.stop(profile.program)
      unless service.ok?
        Util::ActionLog.log("Failed to stop #{profile.program}: #{service.message}")
        return service
      end
      Util::ActionLog.log("Stopped #{profile.program}.")

      route = Caddy::Manager.disable_route(profile.slug)
      Util::ActionLog.log(route.message)
      if route.ok?
        Result.success("Stopped #{profile.name} and disabled its route.")
      else
        Result.failure("#{profile.name} stopped, but its route was not fully disabled: #{route.message}",
          route.detail)
      end
    end

    def self.restart_profile(id : String) : Result
      profile = Profiles::Store.find(id)
      return not_found(id) unless profile

      service = Services::Manager.restart(profile.program)
      Util::ActionLog.log(service.ok? ? "Restarted #{profile.program}." : "Failed to restart #{profile.program}: #{service.message}")
      service.ok? ? Result.success("Restarted #{profile.name}.") : service
    end

    def self.enable_route(id : String) : Result
      profile = Profiles::Store.find(id)
      return not_found(id) unless profile
      result = Caddy::Manager.enable_route(profile)
      Util::ActionLog.log(result.message)
      result
    end

    def self.disable_route(id : String) : Result
      profile = Profiles::Store.find(id)
      return not_found(id) unless profile
      result = Caddy::Manager.disable_route(profile.slug)
      Util::ActionLog.log(result.message)
      result
    end

    def self.validate_caddy : Result
      result = Caddy::Validator.validate_active
      Util::ActionLog.log(result.message)
      result
    end

    def self.reload_caddy : Result
      result = Caddy::Reloader.reload
      Util::ActionLog.log(result.message)
      result
    end

    def self.delete_profile(id : String) : Result
      profile = Profiles::Store.find(id)
      return not_found(id) unless profile
      if Caddy::Snippets.enabled?(profile.slug)
        route = Caddy::Manager.disable_route(profile.slug)
        Util::ActionLog.log(route.message)
      end
      Profiles::Store.delete(profile.slug)
      Util::ActionLog.log("Deleted profile #{profile.slug}.")
      Result.success("Deleted #{profile.name}.")
    end

    private def self.not_found(id : String) : Result
      Result.failure("Profile \"#{id}\" not found.")
    end
  end
end
