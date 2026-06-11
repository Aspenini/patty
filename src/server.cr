module Patty
  module Server
    def self.start
      config = Config.instance
      Util::Paths.ensure_all!
      Caddy::Manager.backend.bootstrap!

      Kemal.config.host_binding = config.server.bind
      Kemal.config.serve_static = false

      Util::ActionLog.log("Patty starting on http://#{config.server.bind}:#{config.server.port}")
      unless Auth.password_set?
        puts "First run: open http://#{config.server.bind}:#{config.server.port} to set an admin password."
      end
      Kemal.run(config.server.port)
    end
  end
end
