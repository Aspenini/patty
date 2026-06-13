require "./spec_helper"

private def security_context(cookie : String? = nil) : HTTP::Server::Context
  headers = HTTP::Headers.new
  headers["Cookie"] = cookie if cookie
  request = HTTP::Request.new("GET", "/", headers)
  HTTP::Server::Context.new(request, HTTP::Server::Response.new(IO::Memory.new))
end

describe Patty::Security::TOTP do
  it "matches the RFC 6238 SHA1 test vectors" do
    secret = "12345678901234567890".to_slice
    vectors = {
                  59_i64 => "94287082",
       1_111_111_109_i64 => "07081804",
       1_111_111_111_i64 => "14050471",
       1_234_567_890_i64 => "89005924",
       2_000_000_000_i64 => "69279037",
      20_000_000_000_i64 => "65353130",
    }

    vectors.each do |timestamp, expected|
      Patty::Security::TOTP.code(secret, Time.unix(timestamp), digits: 8).should eq expected
    end
  end

  it "round-trips Base32 secrets" do
    secret = Random::Secure.random_bytes(20)
    encoded = Patty::Security::TOTP.base32_encode(secret)
    Patty::Security::TOTP.base32_decode(encoded).should eq secret
  end
end

describe Patty::Security::SecretStore do
  it "encrypts, authenticates, and decrypts fallback secrets" do
    fresh_home!
    secret = Random::Secure.random_bytes(20)
    reference = Patty::Security::SecretStore.protect(secret)

    reference.backend.should eq "local-key"
    Patty::Security::SecretStore.unprotect(reference).should eq secret

    encrypted = Base64.decode(reference.ciphertext.to_s)
    encrypted[0] ^= 0xff
    reference.ciphertext = Base64.strict_encode(encrypted)
    expect_raises(Exception) do
      Patty::Security::SecretStore.unprotect(reference)
    end
  end

  {% if flag?(:windows) %}
    it "uses current-user DPAPI on Windows" do
      fresh_home!
      forced = ENV.delete("PATTY_SECRET_STORE")
      begin
        secret = Random::Secure.random_bytes(20)
        reference = Patty::Security::SecretStore.protect(secret)
        reference.backend.should eq "windows-dpapi"
        Patty::Security::SecretStore.unprotect(reference).should eq secret
      ensure
        ENV["PATTY_SECRET_STORE"] = forced || "fallback"
      end
    end
  {% end %}
end

describe Patty::Security::LoginLimiter do
  it "limits per-IP bursts and applies cooldowns" do
    limiter = Patty::Security::LoginLimiter.new
    now = Time.unix(1_700_000_000)

    5.times { limiter.check("203.0.113.10", now).allowed.should be_true }
    denied = limiter.check("203.0.113.10", now)
    denied.allowed.should be_false
    denied.retry_after.should be >= 60
    limiter.check("203.0.113.10", now + 61.seconds).allowed.should be_true

    10.times { limiter.failure!("198.51.100.5", now) }
    cooldown = limiter.check("198.51.100.5", now)
    cooldown.allowed.should be_false
    cooldown.retry_after.should eq 15.minutes.total_seconds.to_i
  end
end

describe "Patty MFA lifecycle" do
  it "enrolls TOTP, rejects replay, and consumes recovery codes once" do
    fresh_home!
    Patty::Auth.set_password("configured-password")
    now = Time.unix(1_700_000_000)
    session = Patty::Auth.create_session(security_context, now: now)
    enrollment = Patty::Auth.begin_enrollment(session, now)
    enrollment.qr_svg.should contain "<svg"
    enrollment.qr_svg.should contain %(aria-label="Authenticator QR code")
    code = Patty::Security::TOTP.code(enrollment.secret, now)

    new_session = Patty::Auth.confirm_enrollment(
      security_context,
      session,
      code,
      secure: false,
      now: now).not_nil!
    codes = new_session.take_recovery_codes.not_nil!

    Patty::Auth.mfa_enabled?.should be_true
    Patty::Auth.recovery_codes_remaining.should eq 10
    Patty::Auth.verify_second_factor(code, now).should be_false
    Patty::Auth.verify_second_factor(codes.first, now).should be_true
    Patty::Auth.verify_second_factor(codes.first, now).should be_false
    Patty::Auth.recovery_codes_remaining.should eq 9
  end

  it "expires idle sessions before their absolute lifetime" do
    fresh_home!
    Patty::Auth.set_password("configured-password")
    now = Time.unix(1_700_000_000)
    response_context = security_context
    session = Patty::Auth.create_session(response_context, now: now)
    cookie = "#{Patty::Auth::SESSION_COOKIE}=#{session.token}"

    Patty::Auth.session_for(
      security_context(cookie),
      now + Patty::Auth::SESSION_IDLE_TIMEOUT + 1.second).should be_nil
  end
end
