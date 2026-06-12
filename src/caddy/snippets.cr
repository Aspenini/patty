module Patty::Caddy
  # Reads/writes <id>.caddy files in the enabled dir. All apply-safety
  # (validate, backup, reload) lives in Manager — these are dumb file ops.
  module Snippets
    def self.path_for(id : String) : String
      File.join(Util::Paths.enabled_dir, "#{File.basename(id)}.caddy")
    end

    def self.render(profile : Profile) : String
      String.build do |io|
        io << "# Managed by Patty — profile: " << profile.slug << '\n'
        io << profile.caddy
        io << '\n' unless profile.caddy.ends_with?('\n')
      end
    end

    def self.write(id : String, content : String)
      Util::AtomicFile.write(path_for(id), content)
    end

    def self.remove(id : String)
      path = path_for(id)
      File.delete(path) if File.exists?(path)
    end

    def self.enabled?(id : String) : Bool
      File.exists?(path_for(id))
    end

    def self.files : Array(String)
      return [] of String unless Dir.exists?(Util::Paths.enabled_dir)

      Dir.children(Util::Paths.enabled_dir)
        .select(&.ends_with?(".caddy"))
        .sort
        .map { |filename| File.join(Util::Paths.enabled_dir, filename) }
    end
  end
end
