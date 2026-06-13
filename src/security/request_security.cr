require "uri"

module Patty::Security::RequestSecurity
  extend self

  def client_ip(env : HTTP::Server::Context) : String
    if trusted_proxy?(env)
      if forwarded = env.request.headers["X-Forwarded-For"]?
        candidate = forwarded.split(',').first?.try(&.strip)
        return candidate if candidate && valid_ip?(candidate)
      end
    end
    socket_ip(env.request.remote_address) || "unknown"
  end

  def https?(env : HTTP::Server::Context) : Bool
    trusted_proxy?(env) &&
      env.request.headers["X-Forwarded-Proto"]?.try(&.split(',').first.strip.downcase) == "https"
  end

  def local_client?(env : HTTP::Server::Context) : Bool
    loopback_ip?(client_ip(env))
  end

  def same_origin?(env : HTTP::Server::Context) : Bool
    origin = env.request.headers["Origin"]?
    return true unless origin
    # Chromium may serialize form origins as "null" under a restrictive
    # referrer policy. Only accept that opaque value from the local server or
    # Patty's trusted loopback Caddy proxy; CSRF validation still follows.
    return trusted_proxy?(env) if origin == "null"
    uri = URI.parse(origin)
    expected_scheme = https?(env) ? "https" : "http"
    expected_host = request_host(env).downcase
    uri.scheme == expected_scheme && authority(uri).downcase == expected_host
  rescue URI::Error
    false
  end

  def trusted_proxy?(env : HTTP::Server::Context) : Bool
    address = socket_ip(env.request.remote_address)
    address ? loopback_ip?(address) : false
  end

  private def socket_ip(address : Socket::Address?) : String?
    case address
    when Socket::IPAddress
      address.address
    else
      nil
    end
  end

  private def valid_ip?(value : String) : Bool
    Socket::IPAddress.new(value, 0)
    true
  rescue Socket::Error
    false
  end

  private def loopback_ip?(value : String) : Bool
    value == "::1" || value.starts_with?("127.")
  end

  private def request_host(env : HTTP::Server::Context) : String
    if trusted_proxy?(env)
      if forwarded = env.request.headers["X-Forwarded-Host"]?
        host = forwarded.split(',').first?.try(&.strip)
        return host if host && !host.empty?
      end
    end
    env.request.headers["Host"]?.to_s
  end

  private def authority(uri : URI) : String
    host = uri.host.to_s
    host = "[#{host}]" if host.includes?(':') && !host.starts_with?('[')
    if port = uri.port
      "#{host}:#{port}"
    else
      host
    end
  end
end
