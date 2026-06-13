require "base64"
require "openssl"
require "openssl/hmac"
require "yaml"

module Patty::Security::SecretStore
  extend self

  FALLBACK_VERSION = "patty-auth-key-v1"

  class Reference
    include YAML::Serializable

    property backend : String
    property reference : String?
    property ciphertext : String?
    property nonce : String?
    property mac : String?

    def initialize(@backend : String, @reference : String? = nil,
                   @ciphertext : String? = nil, @nonce : String? = nil,
                   @mac : String? = nil)
    end
  end

  record Status, backend : String, protected_by_os : Bool, warning : String?

  def protect(secret : Bytes) : Reference
    forced = ENV["PATTY_SECRET_STORE"]?.try(&.downcase)
    return protect_fallback(secret) if forced == "fallback"

    {% if flag?(:windows) %}
      protect_dpapi(secret)
    {% elsif flag?(:darwin) %}
      protect_keychain(secret)
    {% elsif flag?(:linux) %}
      secret_service_available? ? protect_secret_service(secret) : protect_fallback(secret)
    {% else %}
      protect_fallback(secret)
    {% end %}
  rescue ex
    Util::ActionLog.log("Security: OS credential vault unavailable; using protected local key fallback (#{ex.class}).")
    protect_fallback(secret)
  end

  def unprotect(reference : Reference) : Bytes
    case reference.backend
    when "windows-dpapi"
      {% if flag?(:windows) %}
        unprotect_dpapi(reference)
      {% else %}
        raise "Windows DPAPI data cannot be opened on this platform"
      {% end %}
    when "macos-keychain"
      {% if flag?(:darwin) %}
        unprotect_keychain(reference)
      {% else %}
        raise "macOS Keychain data cannot be opened on this platform"
      {% end %}
    when "linux-secret-service"
      {% if flag?(:linux) %}
        unprotect_secret_service(reference)
      {% else %}
        raise "Linux Secret Service data cannot be opened on this platform"
      {% end %}
    when "local-key"
      unprotect_fallback(reference)
    else
      raise "Unknown secret storage backend"
    end
  end

  def delete(reference : Reference)
    case reference.backend
    when "macos-keychain"
      {% if flag?(:darwin) %}
        delete_keychain(reference)
      {% end %}
    when "linux-secret-service"
      {% if flag?(:linux) %}
        delete_secret_service(reference)
      {% end %}
    end
  rescue ex
    Util::ActionLog.log("Security: could not remove an MFA secret from #{reference.backend} (#{ex.class}).")
  end

  def status(reference : Reference? = nil) : Status
    backend = reference.try(&.backend) || preferred_backend
    case backend
    when "windows-dpapi"
      Status.new("Windows DPAPI", true, nil)
    when "macos-keychain"
      Status.new("macOS Keychain", true, nil)
    when "linux-secret-service"
      Status.new("Linux Secret Service", true, nil)
    else
      Status.new(
        "owner-only local key",
        false,
        "The operating-system credential vault is unavailable. MFA is encrypted with a local key file, which does not protect against compromise of the same OS account."
      )
    end
  end

  private def preferred_backend : String
    return "local-key" if ENV["PATTY_SECRET_STORE"]?.try(&.downcase) == "fallback"
    {% if flag?(:windows) %}
      "windows-dpapi"
    {% elsif flag?(:darwin) %}
      "macos-keychain"
    {% elsif flag?(:linux) %}
      secret_service_available? ? "linux-secret-service" : "local-key"
    {% else %}
      "local-key"
    {% end %}
  end

  private def protect_fallback(secret : Bytes) : Reference
    key = fallback_key
    encryption_key = key[0, 32]
    authentication_key = key[32, 32]
    nonce = Random::Secure.random_bytes(16)
    ciphertext = crypt_ctr(secret, encryption_key, nonce, encrypt: true)
    payload = fallback_payload(nonce, ciphertext)
    mac = OpenSSL::HMAC.digest(:sha256, authentication_key, payload)
    Reference.new(
      "local-key",
      ciphertext: Base64.strict_encode(ciphertext),
      nonce: Base64.strict_encode(nonce),
      mac: Base64.strict_encode(mac)
    )
  ensure
    key.try(&.fill(0_u8))
    nonce.try(&.fill(0_u8))
    ciphertext.try(&.fill(0_u8))
    payload.try(&.fill(0_u8))
    mac.try(&.fill(0_u8))
  end

  private def unprotect_fallback(reference : Reference) : Bytes
    ciphertext = Base64.decode(reference.ciphertext.to_s)
    nonce = Base64.decode(reference.nonce.to_s)
    expected_mac = Base64.decode(reference.mac.to_s)
    raise "Invalid encrypted MFA secret" unless nonce.size == 16 && expected_mac.size == 32

    key = fallback_key
    payload = fallback_payload(nonce, ciphertext)
    actual_mac = OpenSSL::HMAC.digest(:sha256, key[32, 32], payload)
    unless ConstantTime.equal?(actual_mac, expected_mac)
      raise "Encrypted MFA secret failed authentication"
    end
    crypt_ctr(ciphertext, key[0, 32], nonce, encrypt: false)
  ensure
    key.try(&.fill(0_u8))
    ciphertext.try(&.fill(0_u8))
    nonce.try(&.fill(0_u8))
    expected_mac.try(&.fill(0_u8))
    payload.try(&.fill(0_u8))
    actual_mac.try(&.fill(0_u8))
  end

  private def fallback_key : Bytes
    path = Util::Paths.auth_key_file
    if File.exists?(path)
      File.open(path, "rb") do |file|
        raise "Invalid authentication key file" unless file.size == 64
        key = Bytes.new(64)
        file.read_fully(key)
        return key
      end
    end

    key = Random::Secure.random_bytes(64)
    Util::AtomicFile.write(path, key, permissions: 0o600)
    key
  end

  private def fallback_payload(nonce : Bytes, ciphertext : Bytes) : Bytes
    io = IO::Memory.new
    io.write(FALLBACK_VERSION.to_slice)
    io.write(nonce)
    io.write(ciphertext)
    io.to_slice.dup
  end

  private def crypt_ctr(data : Bytes, key : Bytes, nonce : Bytes, encrypt : Bool) : Bytes
    cipher = OpenSSL::Cipher.new("aes-256-ctr")
    encrypt ? cipher.encrypt : cipher.decrypt
    cipher.key = key
    cipher.iv = nonce
    first = cipher.update(data)
    last = cipher.final
    output = Bytes.new(first.size + last.size)
    output.copy_from(first)
    output[first.size, last.size].copy_from(last)
    output
  ensure
    first.try(&.fill(0_u8))
    last.try(&.fill(0_u8))
  end

  {% if flag?(:windows) %}
    @[Link("crypt32")]
    lib LibDPAPI
      struct DataBlob
        size : UInt32
        data : UInt8*
      end

      fun CryptProtectData(input : DataBlob*, description : UInt16*,
                           entropy : DataBlob*, reserved : Void*, prompt : Void*,
                           flags : UInt32, output : DataBlob*) : Int32
      fun CryptUnprotectData(input : DataBlob*, description : UInt16**,
                             entropy : DataBlob*, reserved : Void*, prompt : Void*,
                             flags : UInt32, output : DataBlob*) : Int32
    end

    private DPAPI_UI_FORBIDDEN = 0x1_u32

    private def protect_dpapi(secret : Bytes) : Reference
      output = LibDPAPI::DataBlob.new
      begin
        input = LibDPAPI::DataBlob.new(size: secret.size.to_u32, data: secret.to_unsafe)
        result = LibDPAPI.CryptProtectData(
          pointerof(input), Pointer(UInt16).null, Pointer(LibDPAPI::DataBlob).null,
          Pointer(Void).null, Pointer(Void).null, DPAPI_UI_FORBIDDEN, pointerof(output))
        raise IO::Error.from_winerror("DPAPI encryption failed") if result == 0
        encrypted = Bytes.new(output.size.to_i)
        encrypted.copy_from(output.data, output.size.to_i)
        Reference.new("windows-dpapi", ciphertext: Base64.strict_encode(encrypted))
      ensure
        encrypted.try(&.fill(0_u8))
        unless output.data.null?
          output.data.to_slice(output.size.to_i).fill(0_u8)
          LibC.LocalFree(output.data.as(Void*))
        end
      end
    end

    private def unprotect_dpapi(reference : Reference) : Bytes
      output = LibDPAPI::DataBlob.new
      begin
        encrypted = Base64.decode(reference.ciphertext.to_s)
        input = LibDPAPI::DataBlob.new(size: encrypted.size.to_u32, data: encrypted.to_unsafe)
        result = LibDPAPI.CryptUnprotectData(
          pointerof(input), Pointer(Pointer(UInt16)).null, Pointer(LibDPAPI::DataBlob).null,
          Pointer(Void).null, Pointer(Void).null, DPAPI_UI_FORBIDDEN, pointerof(output))
        raise IO::Error.from_winerror("DPAPI decryption failed") if result == 0
        secret = Bytes.new(output.size.to_i)
        secret.copy_from(output.data, output.size.to_i)
        secret
      ensure
        encrypted.try(&.fill(0_u8))
        unless output.data.null?
          output.data.to_slice(output.size.to_i).fill(0_u8)
          LibC.LocalFree(output.data.as(Void*))
        end
      end
    end
  {% end %}

  {% if flag?(:darwin) %}
    @[Link(framework: "Security")]
    lib LibKeychain
      fun SecKeychainAddGenericPassword(keychain : Void*, service_length : UInt32,
                                        service : UInt8*, account_length : UInt32,
                                        account : UInt8*, password_length : UInt32,
                                        password : UInt8*, item : Void**) : Int32
      fun SecKeychainFindGenericPassword(keychain : Void*, service_length : UInt32,
                                         service : UInt8*, account_length : UInt32,
                                         account : UInt8*, password_length : UInt32*,
                                         password : Void**, item : Void**) : Int32
      fun SecKeychainItemModifyAttributesAndData(item : Void*, attributes : Void*,
                                                 length : UInt32, data : UInt8*) : Int32
      fun SecKeychainItemDelete(item : Void*) : Int32
      fun SecKeychainItemFreeContent(attributes : Void*, data : Void*) : Int32
    end

    @[Link(framework: "CoreFoundation")]
    lib LibCoreFoundation
      fun CFRelease(value : Void*)
    end

    private KEYCHAIN_SERVICE   = "org.patty.dashboard.totp"
    private KEYCHAIN_NOT_FOUND = -25300

    private def protect_keychain(secret : Bytes) : Reference
      account = Random::Secure.hex(16)
      status = LibKeychain.SecKeychainAddGenericPassword(
        Pointer(Void).null,
        KEYCHAIN_SERVICE.bytesize.to_u32, KEYCHAIN_SERVICE.to_unsafe,
        account.bytesize.to_u32, account.to_unsafe,
        secret.size.to_u32, secret.to_unsafe,
        Pointer(Pointer(Void)).null)
      raise "macOS Keychain rejected the MFA secret (#{status})" unless status == 0
      Reference.new("macos-keychain", reference: account)
    end

    private def unprotect_keychain(reference : Reference) : Bytes
      account = reference.reference.to_s
      password_length = 0_u32
      password = Pointer(Void).null
      begin
        status = LibKeychain.SecKeychainFindGenericPassword(
          Pointer(Void).null,
          KEYCHAIN_SERVICE.bytesize.to_u32, KEYCHAIN_SERVICE.to_unsafe,
          account.bytesize.to_u32, account.to_unsafe,
          pointerof(password_length), pointerof(password),
          Pointer(Pointer(Void)).null)
        raise "MFA secret was not found in macOS Keychain" unless status == 0
        secret = Bytes.new(password_length.to_i)
        secret.copy_from(password.as(UInt8*), password_length.to_i)
        secret
      ensure
        unless password.null?
          password.as(UInt8*).to_slice(password_length.to_i).fill(0_u8)
          LibKeychain.SecKeychainItemFreeContent(Pointer(Void).null, password)
        end
      end
    end

    private def delete_keychain(reference : Reference)
      account = reference.reference.to_s
      item = Pointer(Void).null
      begin
        status = LibKeychain.SecKeychainFindGenericPassword(
          Pointer(Void).null,
          KEYCHAIN_SERVICE.bytesize.to_u32, KEYCHAIN_SERVICE.to_unsafe,
          account.bytesize.to_u32, account.to_unsafe,
          Pointer(UInt32).null, Pointer(Pointer(Void)).null, pointerof(item))
        return if status == KEYCHAIN_NOT_FOUND
        raise "Could not find macOS Keychain MFA secret (#{status})" unless status == 0
        delete_status = LibKeychain.SecKeychainItemDelete(item)
        raise "Could not delete macOS Keychain MFA secret (#{delete_status})" unless delete_status == 0
      ensure
        LibCoreFoundation.CFRelease(item) unless item.null?
      end
    end
  {% end %}

  {% if flag?(:linux) %}
    private def secret_service_available? : Bool
      !Process.find_executable("secret-tool").nil?
    end

    private def protect_secret_service(secret : Bytes) : Reference
      reference = Random::Secure.hex(16)
      status, _output, error = run_secret_tool(
        ["store", "--label=Patty dashboard MFA", "application", "patty", "id", reference],
        secret)
      raise "Secret Service rejected the MFA secret: #{error.strip}" unless status == 0
      Reference.new("linux-secret-service", reference: reference)
    end

    private def unprotect_secret_service(reference : Reference) : Bytes
      status, output, error = run_secret_tool(
        ["lookup", "application", "patty", "id", reference.reference.to_s])
      raise "MFA secret was not found in Secret Service: #{error.strip}" unless status == 0
      size = output.size
      size -= 1 if size > 0 && output[size - 1] == '\n'.ord
      output[0, size].dup
    ensure
      output.try(&.fill(0_u8))
    end

    private def delete_secret_service(reference : Reference)
      status, output, error = run_secret_tool(
        ["clear", "application", "patty", "id", reference.reference.to_s])
      raise "Could not remove Secret Service MFA secret: #{error.strip}" unless status == 0
    ensure
      output.try(&.fill(0_u8))
    end

    private def run_secret_tool(args : Array(String), input : Bytes? = nil) : {Int32, Bytes, String}
      stdout = IO::Memory.new
      stderr = IO::Memory.new
      source = input ? IO::Memory.new(input) : Process::Redirect::Close
      process = Process.run("secret-tool", args, input: source, output: stdout, error: stderr)
      code = process.normal_exit? ? process.exit_code : 128
      {code, stdout.to_slice.dup, stderr.to_s}
    rescue ex : IO::Error
      {127, Bytes.empty, ex.message.to_s}
    end
  {% else %}
    private def secret_service_available? : Bool
      false
    end
  {% end %}
end
