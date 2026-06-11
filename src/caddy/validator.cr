module Patty::Caddy
  module Validator
    def self.binary : String
      Config.instance.caddy.binary
    end

    def self.found? : Bool
      !Util::ProcessRunner.which(binary).nil?
    end

    def self.validate(config_path : String) : Result
      unless found?
        return Result.failure("Caddy binary \"#{binary}\" not found.",
          "Install Caddy or set the binary path on the Settings page.")
      end
      res = Util::ProcessRunner.run(binary, ["validate", "--config", config_path, "--adapter", "caddyfile"])
      if res.success?
        Result.success("Caddy validation passed.")
      else
        Result.failure("Caddy validation failed.", res.output)
      end
    end

    # Validates the live config (main Caddyfile + enabled snippets).
    def self.validate_active : Result
      Manager.backend.bootstrap!
      validate(Manager.backend.main_caddyfile)
    end
  end
end
