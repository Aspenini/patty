require "openssl/hmac"
require "uri"

module Patty::Security::TOTP
  extend self

  PERIOD       = 30_i64
  DIGITS       =      6
  SECRET_BYTES =     20
  ALPHABET     = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"

  def generate_secret : Bytes
    Random::Secure.random_bytes(SECRET_BYTES)
  end

  def code(secret : Bytes, at : Time = Time.utc, digits : Int32 = DIGITS) : String
    code_for_step(secret, at.to_unix // PERIOD, digits)
  end

  def matching_step(secret : Bytes, submitted : String, at : Time = Time.utc,
                    last_step : Int64 = -1_i64, window : Int32 = 1) : Int64?
    normalized = submitted.strip
    return nil unless normalized.size == DIGITS && normalized.each_char.all?(&.ascii_number?)

    current = at.to_unix // PERIOD
    (-window..window).each do |offset|
      step = current + offset
      next if step <= last_step
      expected = code_for_step(secret, step, DIGITS)
      return step if ConstantTime.equal?(expected, normalized)
    end
    nil
  end

  def base32_encode(bytes : Bytes) : String
    output = String::Builder.new
    buffer = 0_u32
    bits = 0

    bytes.each do |byte|
      buffer = (buffer << 8) | byte
      bits += 8
      while bits >= 5
        bits -= 5
        output << ALPHABET[((buffer >> bits) & 31).to_i]
      end
    end
    output << ALPHABET[((buffer << (5 - bits)) & 31).to_i] if bits > 0
    output.to_s
  end

  def base32_decode(value : String) : Bytes
    clean = value.upcase.gsub(/[\s=-]/, "")
    output = IO::Memory.new
    buffer = 0_u32
    bits = 0

    clean.each_char do |char|
      index = ALPHABET.index(char)
      raise ArgumentError.new("invalid Base32 secret") unless index
      buffer = (buffer << 5) | index
      bits += 5
      if bits >= 8
        bits -= 8
        output.write_byte(((buffer >> bits) & 0xff).to_u8)
      end
    end
    output.to_slice.dup
  end

  def provisioning_uri(secret : String, account : String = "admin") : String
    label = URI.encode_path_segment("Patty:#{account}")
    params = URI::Params.encode({
      "secret"    => secret,
      "issuer"    => "Patty",
      "algorithm" => "SHA1",
      "digits"    => DIGITS.to_s,
      "period"    => PERIOD.to_s,
    })
    "otpauth://totp/#{label}?#{params}"
  end

  private def code_for_step(secret : Bytes, step : Int64, digits : Int32) : String
    message = Bytes.new(8)
    value = step.to_u64
    8.times do |index|
      message[7 - index] = (value & 0xff).to_u8
      value >>= 8
    end

    digest = OpenSSL::HMAC.digest(:sha1, secret, message)
    offset = (digest[-1] & 0x0f).to_i
    binary = ((digest[offset] & 0x7f).to_u32 << 24) |
             (digest[offset + 1].to_u32 << 16) |
             (digest[offset + 2].to_u32 << 8) |
             digest[offset + 3].to_u32
    modulus = 10_u32 ** digits
    (binary % modulus).to_s.rjust(digits, '0')
  ensure
    message.try(&.fill(0_u8))
    digest.try(&.fill(0_u8))
  end
end
