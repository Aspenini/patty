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
      Dir.mkdir_p(Util::Paths.enabled_dir)
      File.write(path_for(id), content)
    end

    def self.remove(id : String)
      path = path_for(id)
      File.delete(path) if File.exists?(path)
    end

    def self.enabled?(id : String) : Bool
      File.exists?(path_for(id))
    end

    def self.files : Array(String)
      Dir.glob(File.join(Util::Paths.enabled_dir, "*.caddy")).sort
    end
  end
end
