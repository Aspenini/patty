module Patty
  module Server
    def self.start
      config = Config.instance
      Util::Paths.ensure_all!
      Caddy::Manager.backend.bootstrap!
      begin
        Caddy::DashboardRoute.sync_file(config)
      rescue ex : ArgumentError
        Util::ActionLog.log("Dashboard route was not applied: #{ex.message}")
      end
      unless Caddy::Snippets.files.empty?
        caddy = Caddy::Manager.reload_active
        Util::ActionLog.log(caddy.message)
        if detail = caddy.detail
          Util::ActionLog.log(detail)
        end
      end
      Core::Watchdog.start

      Kemal.config.host_binding = config.server.bind
      Kemal.config.serve_static = false

      Util::ActionLog.log("Patty starting on http://#{config.server.bind}:#{config.server.port}")
      unless Auth.password_set?
        puts "First run: open http://#{config.server.bind}:#{config.server.port} to set an admin password."
      end
      Kemal.run(config.server.port) do
        Windows::Tray.start
      end
    ensure
      Windows::Tray.stop
    end
  end
end
