module Patty
  VERSION = "0.0.1"

  # Tiny launcher/recovery CLI (spec §6). Everything else lives in the web UI.
  module CLI
    def self.run(args : Array(String))
      case args.first?
      when "run"            then Server.start
      when "setup"          then setup
      when "doctor"         then exit(doctor ? 0 : 1)
      when "reset-password" then reset_password
      when "version"        then version
      when nil, "help", "--help", "-h"
        help
      else
        STDERR.puts "Unknown command: #{args.first?}"
        help
        exit 1
      end
    end

    def self.help
      puts <<-HELP
      Patty — pick your Caddy.

      Usage:
        patty run             Start the Patty web server
        patty setup           First-run setup hints
        patty doctor          Check if the system is ready
        patty reset-password  Clear the admin password (re-runs first-run setup)
        patty version         Show version info
      HELP
    end

    def self.setup
      config = Config.instance
      puts "Patty does its setup in the browser."
      puts "1. Run: patty run"
      puts "2. Open: http://#{config.server.bind}:#{config.server.port}"
      puts "3. Set an admin password and create your first profile."
    end

    def self.version
      puts "Patty v#{VERSION} (#{Util::Platform.name}, Crystal #{Crystal::VERSION})"
    end

    def self.reset_password
      if Auth.password_set?
        Auth.reset_password!
        Util::ActionLog.log("Admin password reset from the CLI.")
        puts "Admin password cleared. Open the web UI to set a new one."
      else
        puts "No admin password is set."
      end
    end

    def self.doctor : Bool
      Util::Paths.ensure_all!
      config = Config.instance
      all_ok = true

      check = ->(label : String, ok : Bool, hint : String?) do
        all_ok = false unless ok
        status = ok ? "OK" : "FAIL"
        puts "#{label.ljust(24)} #{status}#{ok || hint.nil? ? "" : "  (#{hint})"}"
        ok
      end

      check.call("Patty v#{VERSION}", true, nil)
      check.call("Config folder", Dir.exists?(Util::Paths.data_dir), nil)
      check.call("Profiles folder", Dir.exists?(Util::Paths.profiles_dir), nil)
      check.call("Config file", File.exists?(Util::Paths.config_file), nil)

      caddy_found = Caddy::Validator.found?
      check.call("Caddy found", caddy_found, "install caddy or set caddy.binary in patty.yml")

      if caddy_found
        Caddy::Manager.backend.bootstrap!
        validation = Caddy::Validator.validate_active
        check.call("Caddy validate", validation.ok?, validation.detail)
        check.call("Caddy running", Caddy::Reloader.running?,
          "start it with: #{config.caddy.binary} run --config \"#{Caddy::Manager.backend.main_caddyfile}\" --adapter caddyfile")
      end

      if Util::Platform.macos?
        brew = Util::ProcessRunner.run("brew", ["--version"])
        check.call("Homebrew", brew.success?, "install from https://brew.sh")
        if brew.success?
          services = Util::ProcessRunner.run("brew", ["services", "list"])
          check.call("brew services", services.success?, services.output)
        end
      end

      check.call("Admin password set", Auth.password_set?, "open the web UI to run first-run setup")

      puts all_ok ? "\nPatty: OK" : "\nPatty: problems found"
      all_ok
    end
  end
end
