require "file_utils"

module Patty::Caddy
  # Orchestrates the safe-apply flow (spec §27):
  # validate a candidate config in a temp dir → back up → apply → reload.
  # Nothing is written to the enabled dir unless validation passed.
  module Manager
    BACKUPS_TO_KEEP = 20

    @@backend : Backend?

    def self.backend : Backend
      @@backend ||= PortableBackend.new
    end

    def self.enable_route(profile : Profile) : Result
      backend.bootstrap!
      id = profile.slug
      candidate = Snippets.render(profile)

      if Config.instance.caddy.validate_before_reload
        validation = validate_candidate(id, candidate)
        unless validation.ok?
          return Result.failure("Failed to enable route for #{profile.name}: #{validation.message}",
            validation.detail)
        end
      end

      backup!
      Snippets.write(id, candidate)
      finish_apply("Enabled Caddy route #{id}.caddy.")
    end

    def self.disable_route(id : String) : Result
      backend.bootstrap!
      return Result.success("Route #{id} is already disabled.") unless Snippets.enabled?(id)

      if Config.instance.caddy.validate_before_reload
        validation = validate_candidate(id, nil)
        unless validation.ok?
          return Result.failure("Failed to disable route #{id}: #{validation.message}", validation.detail)
        end
      end

      backup!
      Snippets.remove(id)
      finish_apply("Disabled Caddy route #{id}.caddy.")
    end

    # Builds a throwaway copy of the enabled dir with the change applied
    # (content = nil means "snippet removed") and validates that.
    private def self.validate_candidate(id : String, content : String?) : Result
      tmp = File.join(Dir.tempdir, "patty-validate-#{Random::Secure.hex(6)}")
      enabled_tmp = File.join(tmp, "enabled")
      Dir.mkdir_p(enabled_tmp)
      begin
        Snippets.files.each do |file|
          File.copy(file, File.join(enabled_tmp, File.basename(file)))
        end
        candidate_path = File.join(enabled_tmp, "#{id}.caddy")
        if content
          File.write(candidate_path, content)
        else
          File.delete(candidate_path) if File.exists?(candidate_path)
        end
        caddyfile = File.join(tmp, "Caddyfile")
        File.write(caddyfile, %(import "#{enabled_tmp}/*.caddy"\n))
        Validator.validate(caddyfile)
      ensure
        FileUtils.rm_rf(tmp)
      end
    end

    private def self.finish_apply(message : String) : Result
      unless Config.instance.caddy.reload_after_apply
        return Result.success("#{message} Reload skipped (disabled in settings).")
      end
      reload = Reloader.reload
      if reload.ok?
        Result.success("#{message} #{reload.message}")
      else
        # The route file is applied either way; surface the reload problem.
        Result.failure("#{message} But: #{reload.message}", reload.detail)
      end
    end

    # Snapshot of the enabled dir before any change, pruned to the newest N.
    private def self.backup!
      stamp = Time.local.to_s("%Y%m%d-%H%M%S-%L")
      dest = File.join(Util::Paths.backups_dir, stamp)
      Dir.mkdir_p(dest)
      Snippets.files.each do |file|
        File.copy(file, File.join(dest, File.basename(file)))
      end
      prune_backups!
    end

    private def self.prune_backups!
      dirs = Dir.children(Util::Paths.backups_dir).sort
      while dirs.size > BACKUPS_TO_KEEP
        FileUtils.rm_rf(File.join(Util::Paths.backups_dir, dirs.shift))
      end
    end
  end
end
