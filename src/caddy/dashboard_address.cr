require "uri"

module Patty::Caddy::DashboardAddress
  extend self

  def normalize(value : String?) : String?
    raw = value.to_s.strip
    return nil if raw.empty?

    raise ArgumentError.new("dashboard address must not contain whitespace or Caddy syntax") if raw.matches?(/[\s{}]/)

    candidate = raw.includes?("://") ? raw : "https://#{raw}"
    uri = URI.parse(candidate)
    unless {"http", "https"}.includes?(uri.scheme) &&
           uri.host.presence &&
           uri.user.nil? &&
           uri.password.nil? &&
           uri.query.nil? &&
           uri.fragment.nil? &&
           {"", "/"}.includes?(uri.path) &&
           uri.host.not_nil!.matches?(/\A(?:\*\.)?[A-Za-z0-9][A-Za-z0-9.:-]*\z/)
      raise ArgumentError.new("dashboard address must be a hostname or an http(s) URL without a path")
    end

    if uri.scheme == "http" && !local_host?(uri.host.not_nil!)
      raise ArgumentError.new("public dashboard forwarding requires HTTPS")
    end

    if port = uri.port
      unless (1..65535).includes?(port)
        raise ArgumentError.new("dashboard address port must be between 1 and 65535")
      end
    end

    raw.ends_with?("/") ? raw[0...-1] : raw
  rescue ex : URI::Error
    raise ArgumentError.new("dashboard address must be a valid hostname or http(s) URL")
  end

  def browser_url(value : String) : String
    normalized = normalize(value).not_nil!
    normalized.includes?("://") ? normalized : "https://#{normalized}"
  end

  private def local_host?(host : String) : Bool
    normalized = host.downcase
    normalized == "::1" ||
      normalized.starts_with?("127.") ||
      normalized == "localhost" ||
      normalized.ends_with?(".localhost")
  end
end
