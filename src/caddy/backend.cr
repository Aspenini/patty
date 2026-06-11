module Patty::Caddy
  # Where snippets live and which Caddyfile is the entry point.
  # v0.0 ships PortableBackend only; existing-import and patty-managed
  # backends slot in here later (spec §23).
  abstract class Backend
    abstract def enabled_dir : String
    abstract def main_caddyfile : String
    abstract def bootstrap!
  end
end
