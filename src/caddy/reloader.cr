module Patty::Caddy
  module Reloader
    def self.running? : Bool
      Caddy.runtime.running?
    end

    def self.reload : Result
      Caddy.runtime.reload(Manager.backend.main_caddyfile)
    end
  end
end
