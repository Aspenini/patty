module Patty::Caddy
  class PortableBackend < Backend
    def enabled_dir : String
      Util::Paths.enabled_dir
    end

    def main_caddyfile : String
      Util::Paths.active_caddyfile
    end

    def bootstrap!
      Util::Paths.ensure_all!
      return if File.exists?(main_caddyfile)
      Util::AtomicFile.write(main_caddyfile, caddyfile_content(enabled_dir))
    end

    def caddyfile_content(dir : String) : String
      <<-CADDY
      # Managed by Patty — pick your Caddy.
      # This file imports every enabled route snippet.
      import "#{dir}/*.caddy"

      CADDY
    end
  end
end
