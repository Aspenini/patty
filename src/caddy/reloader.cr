require "http/client"

module Patty::Caddy
  module Reloader
    ADMIN_HOST = "127.0.0.1"
    ADMIN_PORT = 2019

    # Caddy's admin API answers on :2019 when a caddy instance is running.
    def self.running? : Bool
      client = HTTP::Client.new(ADMIN_HOST, ADMIN_PORT)
      client.connect_timeout = 1.seconds
      client.read_timeout = 2.seconds
      begin
        client.get("/config/").status_code < 500
      rescue
        false
      ensure
        client.close
      end
    end

    def self.reload : Result
      binary = Config.instance.caddy.binary
      unless Util::ProcessRunner.which(binary)
        return Result.failure("Caddy binary \"#{binary}\" not found.",
          "Install Caddy or set the binary path on the Settings page.")
      end
      main = Manager.backend.main_caddyfile
      unless running?
        return Result.failure("Caddy is not running, so it was not reloaded.",
          "Start it with: #{binary} run --config \"#{main}\" --adapter caddyfile")
      end
      res = Util::ProcessRunner.run(binary, ["reload", "--config", main, "--adapter", "caddyfile"])
      if res.success?
        Result.success("Caddy reload succeeded.")
      else
        Result.failure("Caddy reload failed.", res.output)
      end
    end
  end
end
