require "yaml"

module Patty
  # patty.yml — created with defaults on first run.
  class Config
    include YAML::Serializable

    class ServerSettings
      include YAML::Serializable

      property bind : String = "127.0.0.1"
      property port : Int32 = 7629

      def initialize
      end
    end

    class CaddySettings
      include YAML::Serializable

      property mode : String = "portable"
      property binary : String = "caddy"
      property validate_before_reload : Bool = true
      property reload_after_apply : Bool = true

      def initialize
      end
    end

    property server : ServerSettings = ServerSettings.new
    property caddy : CaddySettings = CaddySettings.new

    def initialize
    end

    @@instance : Config?

    def self.instance : Config
      @@instance ||= load
    end

    def self.reload! : Config
      @@instance = load
    end

    def self.load : Config
      path = Util::Paths.config_file
      if File.exists?(path)
        from_yaml(File.read(path))
      else
        config = new
        config.save
        config
      end
    end

    def save
      Util::AtomicFile.write(Util::Paths.config_file, to_yaml)
    end
  end
end
