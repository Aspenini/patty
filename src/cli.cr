module Patty
  VERSION = "0.1.0"

  # Tiny launcher/recovery CLI (spec §6). Everything else lives in the web UI.
  module CLI
    def self.run(args : Array(String))
      case args.first?
      when "run"            then Server.start
      when "setup"          then setup
      when "doctor"         then exit(doctor ? 0 : 1)
      when "install"        then print_result(Install::Autostart.install)
      when "uninstall"      then print_result(Install::Autostart.uninstall)
      when "reset-password" then reset_password
      when "reset-mfa"      then reset_mfa
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
        patty install         Start Patty automatically after sign-in
        patty uninstall       Remove automatic startup
        patty reset-password  Clear the admin password (re-runs first-run setup)
        patty reset-mfa       Disable MFA using local machine access
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
        route = Caddy::Manager.disable_dashboard
        unless route.ok?
          STDERR.puts "Password was not reset because the public dashboard route could not be disabled."
          STDERR.puts route.message
          STDERR.puts route.detail if route.detail
          exit 1
        end
        Auth.reset_password!
        Util::ActionLog.log("Admin password reset from the CLI.")
        puts "Admin password and MFA cleared. Public dashboard forwarding is disabled until setup is complete."
      else
        puts "No admin password is set."
      end
    end

    def self.reset_mfa
      if Auth.mfa_enabled?
        Auth.reset_mfa!
        Util::ActionLog.log("Security: MFA reset from the local CLI.")
        puts "MFA disabled and all dashboard sessions revoked."
      else
        puts "MFA is not enabled."
      end
    end

    def self.doctor : Bool
      Util::Paths.ensure_all!
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
      autostart = Install::Autostart.installed?
      puts "#{"Automatic startup".ljust(24)} #{autostart ? "OK" : "OFF"}#{autostart ? "" : "  (optional: run patty install)"}"

      caddy_found = Caddy::Validator.found?
      check.call("Caddy found", caddy_found, "install caddy or set caddy.binary in patty.yml")

      if caddy_found
        Caddy::Manager.backend.bootstrap!
        validation = Caddy::Validator.validate_active
        check.call("Caddy validate", validation.ok?, validation.detail)
        check.call("Caddy running", Caddy::Reloader.running?,
          "use Start / Reload Caddy in the dashboard")
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

      caddy_running = Caddy::Reloader.running?
      Profiles::Store.all.each do |profile|
        next unless Caddy::Snippets.enabled?(profile.slug)

        if program = profile.program
          service, adapter = Services::Manager.status(program)
          check.call(
            "#{profile.slug} service",
            service.running?,
            adapter ? "#{adapter}: #{service.label}" : "no service adapter found"
          )
        end

        health = Core::Health::Checker.check(profile, true, caddy_running)
        check.call("#{profile.slug} route", health.state.healthy?, health.detail)
      end

      puts all_ok ? "\nPatty: OK" : "\nPatty: problems found"
      all_ok
    end

    private def self.print_result(result : Result)
      output = result.ok? ? STDOUT : STDERR
      output.puts result.message
      output.puts result.detail if result.detail
      exit 1 unless result.ok?
    end
  end
end
