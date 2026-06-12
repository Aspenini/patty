module Patty::Caddy
  module Reloader
    def self.running? : Bool
      Caddy.runtime.running?
    end

    def self.reload : Result
      config_path = Manager.backend.main_caddyfile
      if Caddy.runtime.running?
        Caddy.runtime.reload(config_path)
      else
        Caddy.runtime.start(config_path)
      end
    end
  end
end
