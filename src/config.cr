require "yaml"

module Patty
  # patty.yml — created with defaults on first run.
  class Config
    include YAML::Serializable
    include YAML::Serializable::Strict

    class ServerSettings
      include YAML::Serializable
      include YAML::Serializable::Strict

      property bind : String = "127.0.0.1"
      property port : Int32 = 7629

      def initialize
      end
    end

    class CaddySettings
      include YAML::Serializable
      include YAML::Serializable::Strict

      property mode : String = "portable"
      property binary : String = "caddy"
      property dashboard_address : String? = nil
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

    def errors : Array(String)
      values = [] of String
      values << "bind address must not be empty" if server.bind.strip.empty?
      values << "port must be between 1 and 65535" unless (1..65535).includes?(server.port)
      values << "Caddy binary must not be empty" if caddy.binary.strip.empty?
      values << "only portable Caddy mode is supported" unless caddy.mode == "portable"
      begin
        Caddy::DashboardAddress.normalize(caddy.dashboard_address)
      rescue ex : ArgumentError
        values << ex.message.to_s
      end
      values
    end
  end
end
