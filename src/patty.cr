require "yaml"
require "json"
require "kemal"

require "./util/platform"
require "./util/paths"
require "./util/atomic_file"
require "./util/process_runner"
require "./util/logging"
require "./core/result"
require "./install/autostart"
require "./caddy/dashboard_address"
require "./config"
require "./profiles/id_generator"
require "./profiles/profile"
require "./profiles/parser"
require "./profiles/validator"
require "./profiles/warnings"
require "./profiles/store"
require "./caddy/backend"
require "./caddy/portable_backend"
require "./caddy/snippets"
require "./caddy/dashboard_route"
require "./caddy/runtime"
require "./caddy/validator"
require "./caddy/reloader"
require "./caddy/manager"
require "./services/adapter"
require "./services/mac_brew_adapter"
require "./services/linux_systemd_adapter"
require "./services/windows_service_adapter"
require "./services/manager"
require "./core/health"
require "./core/actions"
require "./core/state"
require "./core/watchdog"
require "./auth"
require "./windows/tray"
require "./web/render"
require "./web/routes"
require "./server"
require "./cli"

{% if flag?(:windows_gui) %}
  Patty::Util::Paths.ensure_all!
  File.open(Patty::Util::Paths.log_file, "a") do |log|
    STDOUT.reopen(log)
    STDERR.reopen(log)
  end
  Patty::Server.start unless Patty::Windows::Tray.open_existing
{% else %}
  Patty::CLI.run(ARGV)
{% end %}
