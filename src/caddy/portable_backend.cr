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
      content = caddyfile_content(enabled_dir)
      return if File.exists?(main_caddyfile) && File.read(main_caddyfile) == content
      Util::AtomicFile.write(main_caddyfile, content)
    end

    def caddyfile_content(dir : String) : String
      import_dir = dir.gsub('\\', '/')
      <<-CADDY
      # Managed by Patty — pick your Caddy.
      # This file imports every enabled route snippet.
      import "#{import_dir}/*.caddy"

      CADDY
    end
  end
end
