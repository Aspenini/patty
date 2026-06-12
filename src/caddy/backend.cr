module Patty::Caddy
  # Where snippets live and which Caddyfile is the entry point.
  # Portable mode owns a generated Caddyfile and imported snippet directory.
  abstract class Backend
    abstract def enabled_dir : String
    abstract def main_caddyfile : String
    abstract def bootstrap!
  end
end
