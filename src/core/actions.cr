module Patty::Core
  # The single choke point for everything the web UI (and any future CLI
  # command) can do. Every action logs what it did (spec §11).
  module Actions
    @@mutation_mutex = Mutex.new

    def self.start_profile(id : String) : Result
      @@mutation_mutex.synchronize do
        profile = Profiles::Store.find(id)
        return not_found(id) unless profile
        initial_status, _ = Services::Manager.status(profile.program)

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
          compensate_start(profile, initial_status, route)
        end
      end
    end

    def self.stop_profile(id : String) : Result
      @@mutation_mutex.synchronize do
        profile = Profiles::Store.find(id)
        return not_found(id) unless profile
        initial_status, _ = Services::Manager.status(profile.program)

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
          compensate_stop(profile, initial_status, route)
        end
      end
    end

    def self.restart_profile(id : String) : Result
      @@mutation_mutex.synchronize do
        profile = Profiles::Store.find(id)
        return not_found(id) unless profile

        service = Services::Manager.restart(profile.program)
        Util::ActionLog.log(service.ok? ? "Restarted #{profile.program}." : "Failed to restart #{profile.program}: #{service.message}")
        service.ok? ? Result.success("Restarted #{profile.name}.") : service
      end
    end

    def self.enable_route(id : String) : Result
      @@mutation_mutex.synchronize do
        profile = Profiles::Store.find(id)
        return not_found(id) unless profile
        result = Caddy::Manager.enable_route(profile)
        Util::ActionLog.log(result.message)
        result
      end
    end

    def self.disable_route(id : String) : Result
      @@mutation_mutex.synchronize do
        profile = Profiles::Store.find(id)
        return not_found(id) unless profile
        result = Caddy::Manager.disable_route(profile.slug)
        Util::ActionLog.log(result.message)
        result
      end
    end

    def self.validate_caddy : Result
      result = Caddy::Validator.validate_active
      Util::ActionLog.log(result.message)
      result
    end

    def self.reload_caddy : Result
      result = Caddy::Manager.reload_active
      Util::ActionLog.log(result.message)
      result
    end

    def self.delete_profile(id : String) : Result
      @@mutation_mutex.synchronize do
        profile = Profiles::Store.find(id)
        return not_found(id) unless profile
        route_was_enabled = Caddy::Snippets.enabled?(profile.slug)

        if route_was_enabled
          route = Caddy::Manager.disable_route(profile.slug)
          Util::ActionLog.log(route.message)
          return Result.failure("Could not delete #{profile.name} because its route could not be disabled.",
            join_details(route.message, route.detail)) unless route.ok?
        end

        begin
          Profiles::Store.delete(profile.slug)
        rescue ex
          rollback = route_was_enabled ? Caddy::Manager.enable_route(profile) : nil
          Util::ActionLog.log("Failed to delete profile #{profile.slug}: #{ex.message}")
          Util::ActionLog.log(rollback.message) if rollback
          return Result.failure(
            "Could not delete #{profile.name}; its profile file could not be removed.",
            join_details(ex.message, rollback_detail(rollback)))
        end

        Util::ActionLog.log("Deleted profile #{profile.slug}.")
        Result.success("Deleted #{profile.name}.")
      end
    end

    def self.update_profile(id : String, profile : Profile) : Result
      @@mutation_mutex.synchronize do
        existing = Profiles::Store.find(id)
        return not_found(id) unless existing

        profile.id = existing.slug
        errors = Profiles::Validator.validate(profile)
        unless errors.empty?
          return Result.failure("Profile validation failed.", errors.join("\n"))
        end

        route_was_enabled = Caddy::Snippets.enabled?(existing.slug)
        if route_was_enabled
          route = Caddy::Manager.enable_route(profile)
          Util::ActionLog.log(route.message)
          return route unless route.ok?
        end

        begin
          Profiles::Store.save(profile)
        rescue ex
          rollback = route_was_enabled ? Caddy::Manager.enable_route(existing) : nil
          Util::ActionLog.log("Failed to save profile #{existing.slug}: #{ex.message}")
          Util::ActionLog.log(rollback.message) if rollback
          return Result.failure(
            "Profile #{existing.name} could not be saved.",
            join_details(ex.message, rollback_detail(rollback)))
        end

        Util::ActionLog.log("Updated profile #{profile.slug}.")
        Result.success("Profile #{profile.name} saved.")
      end
    end

    private def self.not_found(id : String) : Result
      Result.failure("Profile \"#{id}\" not found.")
    end

    private def self.compensate_start(profile : Profile, initial_status : Services::Status,
                                      route : Result) : Result
      unless initial_status.stopped?
        return Result.failure(
          "#{profile.name} started, but its route could not be enabled.",
          join_details(route.message, route.detail, "Service compensation skipped because its prior state was #{initial_status.label}."))
      end

      compensation = Services::Manager.stop(profile.program)
      Util::ActionLog.log(compensation.ok? ? "Stopped #{profile.program} to compensate for route failure." : "Failed to compensate start of #{profile.program}: #{compensation.message}")
      message = compensation.ok? ? "#{profile.name} could not be started; the service was restored to stopped." : "#{profile.name} started, its route failed, and restoring the service also failed."
      Result.failure(message, join_details(route.message, route.detail, compensation_detail(compensation)))
    end

    private def self.compensate_stop(profile : Profile, initial_status : Services::Status,
                                     route : Result) : Result
      unless initial_status.running?
        return Result.failure(
          "#{profile.name} stopped, but its route could not be disabled.",
          join_details(route.message, route.detail, "Service compensation skipped because its prior state was #{initial_status.label}."))
      end

      compensation = Services::Manager.start(profile.program)
      Util::ActionLog.log(compensation.ok? ? "Started #{profile.program} to compensate for route failure." : "Failed to compensate stop of #{profile.program}: #{compensation.message}")
      message = compensation.ok? ? "#{profile.name} could not be stopped; the service was restored to running." : "#{profile.name} stopped, its route failed, and restoring the service also failed."
      Result.failure(message, join_details(route.message, route.detail, compensation_detail(compensation)))
    end

    private def self.compensation_detail(result : Result) : String
      result.ok? ? result.message : "Compensation failed: #{result.message}\n#{result.detail}".strip
    end

    private def self.rollback_detail(result : Result?) : String?
      return nil unless result
      prefix = result.ok? ? "Route rollback succeeded: " : "Route rollback failed: "
      "#{prefix}#{result.message}\n#{result.detail}".strip
    end

    private def self.join_details(*parts : String?) : String?
      detail = parts.compact_map(&.presence).join("\n")
      detail.presence
    end
  end
end
