# Specs run against an isolated PATTY_HOME so they never touch real data.
ENV["PATTY_HOME"] = File.join(Dir.tempdir, "patty-spec-#{Random::Secure.hex(6)}")

require "spec"
require "yaml"
require "file_utils"

require "../src/util/platform"
require "../src/util/paths"
require "../src/util/process_runner"
require "../src/util/logging"
require "../src/core/result"
require "../src/config"
require "../src/profiles/id_generator"
require "../src/profiles/profile"
require "../src/profiles/parser"
require "../src/profiles/validator"
require "../src/profiles/store"
require "../src/caddy/backend"
require "../src/caddy/portable_backend"
require "../src/caddy/snippets"
require "../src/caddy/validator"
require "../src/caddy/reloader"
require "../src/caddy/manager"

Spec.after_suite do
  FileUtils.rm_rf(ENV["PATTY_HOME"])
end

def fresh_home!
  FileUtils.rm_rf(Patty::Util::Paths.data_dir)
  Patty::Util::Paths.ensure_all!
end
