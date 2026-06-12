require "yaml"
require "uri"

module Patty
  # Pattyfile identity comes from its filename and is never serialized.
  class Profile
    include YAML::Serializable
    include YAML::Serializable::Strict

    property program : String?
    property caddy : String

    @[YAML::Field(ignore: true)]
    property id : String?

    def initialize(@caddy : String, @program : String? = nil, @id : String? = nil)
    end

    def slug : String
      id || raise "Profile identity has not been assigned from a filename"
    end

    def name : String
      slug
    end

    # Canonical .pattyfile output used for storage and export.
    def to_pattyfile : String
      String.build do |io|
        if value = program
          io << "program: " << yaml_scalar(value) << "\n\n"
        end
        io << "caddy: |\n"
        caddy.each_line(chomp: true) do |line|
          if line.empty?
            io << '\n'
          else
            io << "  " << line << '\n'
          end
        end
      end
    end

    # First site address in the Caddy snippet, turned into something a
    # browser can open. Best effort — nil when nothing usable is found.
    def open_url : String?
      caddy.each_line(chomp: true) do |line|
        stripped = line.strip
        next if stripped.empty? || stripped.starts_with?('#')
        host = stripped.split(/[\s{,]/).first?.try(&.strip)
        next if host.nil? || host.empty?
        candidate =
          if host.includes?("://")
            host
          elsif host.starts_with?(':')
            "http://localhost#{host}"
          else
            "https://#{host}"
          end
        uri = URI.parse(candidate)
        return nil unless {"http", "https"}.includes?(uri.scheme) && uri.host.try(&.presence)
        return candidate
      end
      nil
    rescue URI::Error
      nil
    end

    private def yaml_scalar(value : String) : String
      if value.matches?(/\A[A-Za-z0-9][A-Za-z0-9 ._-]*\z/) && !value.ends_with?(' ')
        value
      else
        value.inspect
      end
    end
  end
end
