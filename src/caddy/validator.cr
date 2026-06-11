module Patty::Caddy
  module Validator
    def self.binary : String
      Config.instance.caddy.binary
    end

    def self.found? : Bool
      Caddy.runtime.found?
    end

    def self.validate(config_path : String) : Result
      Caddy.runtime.validate(config_path)
    end

    # Validates the live config (main Caddyfile + enabled snippets).
    def self.validate_active : Result
      Manager.validate_active
    end
  end
end
