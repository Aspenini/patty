# Specs run against an isolated PATTY_HOME so they never touch real data.
ENV["PATTY_HOME"] = File.join(Dir.tempdir, "patty-spec-#{Random::Secure.hex(6)}")

require "spec"
require "yaml"
require "file_utils"

require "../src/util/platform"
require "../src/util/paths"
require "../src/util/atomic_file"
require "../src/util/process_runner"
require "../src/util/logging"
require "../src/core/result"
require "../src/install/autostart"
require "../src/caddy/dashboard_address"
require "../src/config"
require "../src/profiles/id_generator"
require "../src/profiles/profile"
require "../src/profiles/parser"
require "../src/profiles/validator"
require "../src/profiles/warnings"
require "../src/profiles/store"
require "../src/caddy/backend"
require "../src/caddy/portable_backend"
require "../src/caddy/snippets"
require "../src/caddy/dashboard_route"
require "../src/caddy/runtime"
require "../src/caddy/validator"
require "../src/caddy/reloader"
require "../src/caddy/manager"
require "../src/services/adapter"
require "../src/services/mac_brew_adapter"
require "../src/services/linux_systemd_adapter"
require "../src/services/windows_service_adapter"
require "../src/services/manager"
require "../src/core/health"
require "../src/core/actions"
require "../src/core/watchdog"
require "../src/auth"

Spec.after_suite do
  FileUtils.rm_rf(ENV["PATTY_HOME"])
end

Spec.after_each do
  Patty::Caddy.reset_runtime!
  Patty::Services::Manager.reset_adapters!
  Patty::Core::Health::Checker.reset!
end

def fresh_home!
  FileUtils.rm_rf(Patty::Util::Paths.data_dir)
  Patty::Util::Paths.ensure_all!
  Patty::Config.reload!
end

class FakeCaddyRuntime < Patty::Caddy::Runtime
  getter validate_calls = [] of String
  getter start_calls = [] of String
  getter reload_calls = [] of String
  property validate_results = [] of Patty::Result
  property start_results = [] of Patty::Result
  property reload_results = [] of Patty::Result
  property found = true
  property running = true

  def found? : Bool
    found
  end

  def running? : Bool
    running
  end

  def validate(config_path : String) : Patty::Result
    @validate_calls << config_path
    @validate_results.shift? || Patty::Result.success("Caddy validation passed.")
  end

  def start(config_path : String) : Patty::Result
    @start_calls << config_path
    result = @start_results.shift? || Patty::Result.success("Caddy started.")
    @running = true if result.ok?
    result
  end

  def reload(config_path : String) : Patty::Result
    @reload_calls << config_path
    @reload_results.shift? || Patty::Result.success("Caddy reload succeeded.")
  end
end

class FakeServiceAdapter < Patty::Services::Adapter
  getter actions = [] of String
  property current_status : Patty::Services::Status
  property start_results = [] of Patty::Result
  property stop_results = [] of Patty::Result
  property restart_results = [] of Patty::Result

  def initialize(@current_status : Patty::Services::Status)
  end

  def name : String
    "fake service"
  end

  def available?(program : String) : Bool
    true
  end

  def start(program : String) : Patty::Result
    @actions << "start"
    result = @start_results.shift? || Patty::Result.success("started")
    @current_status = Patty::Services::Status::Running if result.ok?
    result
  end

  def stop(program : String) : Patty::Result
    @actions << "stop"
    result = @stop_results.shift? || Patty::Result.success("stopped")
    @current_status = Patty::Services::Status::Stopped if result.ok?
    result
  end

  def restart(program : String) : Patty::Result
    @actions << "restart"
    @restart_results.shift? || Patty::Result.success("restarted")
  end

  def status(program : String) : Patty::Services::Status
    @current_status
  end
end
