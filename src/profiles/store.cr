module Patty::Profiles
  # Profiles live as <id>.pattyfile in the profiles dir. Loaded fresh on each
  # request — file counts are tiny and it keeps things cache-free.
  module Store
    @@mutation_mutex = Mutex.new

    def self.all : Array(Profile)
      return [] of Profile unless Dir.exists?(Util::Paths.profiles_dir)

      Dir.children(Util::Paths.profiles_dir)
        .select(&.ends_with?(".pattyfile"))
        .sort
        .compact_map do |filename|
          path = File.join(Util::Paths.profiles_dir, filename)
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

    # Writes canonical YAML under the identity assigned from a filename.
    def self.save(profile : Profile) : Profile
      @@mutation_mutex.synchronize do
        Dir.mkdir_p(Util::Paths.profiles_dir)
        id = profile.id
        raise ArgumentError.new("profile identity is required") unless id
        unless Validator::ID_RE.matches?(id)
          raise ArgumentError.new("profile identity must be a lowercase slug")
        end
        Util::AtomicFile.write(path_for(profile.slug), profile.to_pattyfile)
        profile
      end
    end

    def self.delete(id : String)
      @@mutation_mutex.synchronize do
        path = path_for(id)
        return unless File.exists?(path)

        tombstone = "#{path}.delete-#{Random::Secure.hex(8)}"
        File.rename(path, tombstone)
        begin
          File.delete(tombstone)
        rescue ex
          File.rename(tombstone, path) if File.exists?(tombstone) && !File.exists?(path)
          raise ex
        end
      end
    end

    def self.path_for(id : String) : String
      # ids are validated slugs, but never trust them as path components
      File.join(Util::Paths.profiles_dir, "#{File.basename(id)}.pattyfile")
    end
  end
end
