module Patty::Profiles
  # Profiles live as <id>.pattyfile in the profiles dir. Loaded fresh on each
  # request — file counts are tiny and it keeps things cache-free.
  module Store
    def self.all : Array(Profile)
      Dir.glob(File.join(Util::Paths.profiles_dir, "*.pattyfile")).sort.compact_map do |path|
        begin
          profile = Parser.parse(File.read(path))
          profile.id ||= File.basename(path, ".pattyfile")
          profile
        rescue Profiles::ParseError
          nil
        end
      end
    end

    def self.ids : Array(String)
      all.map(&.slug)
    end

    def self.find(id : String) : Profile?
      path = path_for(id)
      return nil unless File.exists?(path)
      profile = Parser.parse(File.read(path))
      profile.id ||= id
      profile
    rescue Profiles::ParseError
      nil
    end

    def self.exists?(id : String) : Bool
      File.exists?(path_for(id))
    end

    # Assigns a collision-free id when missing, then writes canonical YAML.
    def self.save(profile : Profile) : Profile
      Dir.mkdir_p(Util::Paths.profiles_dir)
      if profile.id.nil?
        profile.id = IdGenerator.generate(profile.name, ids)
      end
      File.write(path_for(profile.slug), profile.to_pattyfile)
      profile
    end

    def self.delete(id : String)
      path = path_for(id)
      File.delete(path) if File.exists?(path)
    end

    def self.path_for(id : String) : String
      # ids are validated slugs, but never trust them as path components
      File.join(Util::Paths.profiles_dir, "#{File.basename(id)}.pattyfile")
    end
  end
end
