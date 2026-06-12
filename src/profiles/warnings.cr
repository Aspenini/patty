require "uri"

module Patty::Profiles::Warnings
  def self.for(profile : Profile) : Array(String)
    warnings = [] of String
    if public_file_server?(profile)
      warnings << "This file server uses a public hostname without obvious Caddy access control. Its files may be reachable from the internet."
    end
    warnings
  end

  private def self.public_file_server?(profile : Profile) : Bool
    directives = profile.caddy.each_line.map(&.strip).reject(&.starts_with?('#')).to_a
    return false unless directives.any?(&.starts_with?("file_server"))
    return false if directives.any? { |line| line.starts_with?("basic_auth") || line.starts_with?("forward_auth") }

    url = profile.open_url
    return false unless url
    host = URI.parse(url).host
    !!(host && !local_host?(host))
  rescue URI::Error
    false
  end

  private def self.local_host?(host : String) : Bool
    value = host.downcase
    return true if value == "localhost" || value.ends_with?(".localhost") || value.ends_with?(".local")
    return true if value == "::1" || value.starts_with?("fc") || value.starts_with?("fd") || value.starts_with?("fe80:")

    parts = value.split('.').map(&.to_i?)
    return false unless parts.size == 4 && parts.all?
    octets = parts.compact
    octets[0] == 10 ||
      octets[0] == 127 ||
      (octets[0] == 169 && octets[1] == 254) ||
      (octets[0] == 172 && (16..31).includes?(octets[1])) ||
      (octets[0] == 192 && octets[1] == 168)
  end
end
