require "yaml"
require "uri"

module Patty
  # A parsed .pattyfile. Simple format only in v0.0:
  # required patty/name/program/caddy, optional id/description/category.
  class Profile
    include YAML::Serializable

    property patty : Int32
    property name : String
    property program : String
    property caddy : String
    property id : String?
    property description : String?
    property category : String?

    def initialize(@patty : Int32, @name : String, @program : String, @caddy : String,
                   @id : String? = nil, @description : String? = nil, @category : String? = nil)
    end

    def slug : String
      id || Profiles::IdGenerator.slugify(name)
    end

    # Canonical .pattyfile output used for storage and export.
    def to_pattyfile : String
      String.build do |io|
        io << "patty: " << patty << "\n\n"
        io << "name: " << yaml_scalar(name) << '\n'
        if value = id
          io << "id: " << yaml_scalar(value) << '\n'
        end
        if value = description
          io << "description: " << yaml_scalar(value) << '\n'
        end
        if value = category
          io << "category: " << yaml_scalar(value) << '\n'
        end
        io << "program: " << yaml_scalar(program) << "\n\n"
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
