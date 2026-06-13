require "base64"
require "crypto/bcrypt/password"
require "digest/sha256"
require "http/server"
require "qr-code"
require "yaml"

module Patty
  module Auth
    VERSION                 = 2
    PASSWORD_ALGORITHM      = "bcrypt-sha256"
    SESSION_COOKIE          = "patty_session"
    FORM_CSRF_COOKIE        = "patty_form_csrf"
    MFA_CHALLENGE_COOKIE    = "patty_mfa_challenge"
    SESSION_IDLE_TIMEOUT    = 2.hours
    SESSION_MAX_AGE         = 7.days
    MFA_CHALLENGE_MAX_AGE   = 5.minutes
    MFA_CHALLENGE_MAX_TRIES = 5
    ENROLLMENT_MAX_AGE      = 10.minutes
    RECOVERY_CODE_COUNT     = 10

    class MfaState
      include YAML::Serializable

      property secret : Security::SecretStore::Reference
      property recovery_hashes : Array(String)
      property last_totp_step : Int64 = -1_i64

      def initialize(@secret : Security::SecretStore::Reference,
                     @recovery_hashes : Array(String),
                     @last_totp_step : Int64 = -1_i64)
      end
    end

    class Data
      include YAML::Serializable

      property version : Int32 = VERSION
      property password_algorithm : String = PASSWORD_ALGORITHM
      property password_hash : String
      property generation : String
      property mfa : MfaState?

      def initialize(@password_hash : String, @generation : String,
                     @password_algorithm : String = PASSWORD_ALGORITHM,
                     @mfa : MfaState? = nil, @version : Int32 = VERSION)
      end
    end

    class Session
      getter token : String
      getter csrf_token : String
      getter created_at : Time
      getter credential_generation : String
      getter last_seen : Time
      @flash : {String, String}?
      @recovery_codes : Array(String)?

      def initialize(@credential_generation : String, now : Time = Time.utc)
        @token = Random::Secure.urlsafe_base64(32)
        @csrf_token = Random::Secure.urlsafe_base64(32)
        @created_at = now
        @last_seen = now
      end

      def expired?(now : Time = Time.utc) : Bool
        (now - created_at) > SESSION_MAX_AGE ||
          (now - last_seen) > SESSION_IDLE_TIMEOUT
      end

      def touch(now : Time = Time.utc)
        @last_seen = now
      end

      def flash!(kind : String, message : String)
        @flash = {kind, message}
      end

      def flash(result : Result)
        flash!(result.kind, result.detail ? "#{result.message}\n#{result.detail}" : result.message)
      end

      def take_flash : {String, String}?
        value = @flash
        @flash = nil
        value
      end

      def recovery_codes=(codes : Array(String))
        @recovery_codes = codes
      end

      def take_recovery_codes : Array(String)?
        value = @recovery_codes
        @recovery_codes = nil
        value
      end
    end

    class PendingChallenge
      getter token : String
      getter ip : String
      getter created_at : Time
      property attempts : Int32

      def initialize(@ip : String, now : Time = Time.utc)
        @token = Random::Secure.urlsafe_base64(32)
        @created_at = now
        @attempts = 0
      end

      def expired?(now : Time = Time.utc) : Bool
        (now - created_at) > MFA_CHALLENGE_MAX_AGE ||
          attempts >= MFA_CHALLENGE_MAX_TRIES
      end
    end

    class Enrollment
      getter secret : Bytes
      getter created_at : Time

      def initialize(now : Time = Time.utc)
        @secret = Security::TOTP.generate_secret
        @created_at = now
      end

      def expired?(now : Time = Time.utc) : Bool
        (now - created_at) > ENROLLMENT_MAX_AGE
      end

      def manual_key : String
        Security::TOTP.base32_encode(secret)
      end

      def provisioning_uri : String
        Security::TOTP.provisioning_uri(manual_key)
      end

      def qr_svg : String
        qr = QRCode.new(provisioning_uri, level: :m)
        offset = 4
        module_size = 5
        dimension = qr.module_count * module_size + offset * 2
        content = qr.as_svg(
          offset: offset,
          color: "111827",
          module_size: module_size,
          standalone: false,
          fill: "ffffff")
        %(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 #{dimension} #{dimension}" ) +
          %(width="#{dimension}" height="#{dimension}" shape-rendering="crispEdges" ) +
          %(role="img" aria-label="Authenticator QR code">#{content}</svg>)
      end

      def wipe!
        secret.fill(0_u8)
      end
    end

    @@sessions = {} of String => Session
    @@challenges = {} of String => PendingChallenge
    @@enrollments = {} of String => Enrollment
    @@session_mutex = Mutex.new
    @@state_mutex = Mutex.new
    @@login_limiter = Security::LoginLimiter.new

    def self.password_set? : Bool
      !load_data.nil?
    end

    def self.set_password(password : String)
      password_hash = create_password_hash(password)
      data = Data.new(password_hash, new_generation)
      @@state_mutex.synchronize { save_data(data) }
      clear_runtime_credentials!
    end

    def self.verify_password(password : String) : Bool
      data = load_data
      return false unless data
      valid = verify_password_hash(data, password)
      upgrade_password_hash(data, password) if valid && data.password_algorithm != PASSWORD_ALGORITHM
      valid
    rescue
      false
    end

    def self.password_algorithm : String?
      load_data.try(&.password_algorithm)
    end

    def self.mfa_enabled? : Bool
      !load_data.try(&.mfa).nil?
    end

    def self.recovery_codes_remaining : Int32
      load_data.try(&.mfa).try(&.recovery_hashes.size) || 0
    end

    def self.secret_store_status : Security::SecretStore::Status
      Security::SecretStore.status(load_data.try(&.mfa).try(&.secret))
    end

    def self.reset_password!
      data = load_data
      if mfa = data.try(&.mfa)
        Security::SecretStore.delete(mfa.secret)
      end
      File.delete(Util::Paths.auth_file) if File.exists?(Util::Paths.auth_file)
      File.delete(Util::Paths.auth_key_file) if File.exists?(Util::Paths.auth_key_file)
      clear_runtime_credentials!
    end

    def self.reset_mfa! : Bool
      @@state_mutex.synchronize do
        data = load_data
        return false unless data
        if mfa = data.mfa
          Security::SecretStore.delete(mfa.secret)
          data.mfa = nil
          data.generation = new_generation
          save_data(data)
        end
      end
      clear_runtime_credentials!
      true
    end

    def self.create_session(env : HTTP::Server::Context,
                            secure : Bool = Security::RequestSecurity.https?(env),
                            now : Time = Time.utc) : Session
      generation = current_generation
      raise "Cannot create a session without configured credentials" unless generation
      session = Session.new(generation, now)
      @@session_mutex.synchronize { @@sessions[session.token] = session }
      set_cookie(env, SESSION_COOKIE, session.token, secure, SESSION_MAX_AGE)
      session
    end

    def self.session_for(env : HTTP::Server::Context, now : Time = Time.utc) : Session?
      token = env.request.cookies[SESSION_COOKIE]?.try(&.value)
      return nil unless token
      session = @@session_mutex.synchronize { @@sessions[token]? }
      generation = current_generation
      if session && (session.expired?(now) || generation.nil? ||
         session.credential_generation != generation)
        @@session_mutex.synchronize { @@sessions.delete(token) }
        return nil
      end
      if session
        @@session_mutex.synchronize { session.touch(now) }
      end
      session
    end

    def self.destroy_session(env : HTTP::Server::Context)
      if token = env.request.cookies[SESSION_COOKIE]?.try(&.value)
        @@session_mutex.synchronize { @@sessions.delete(token) }
      end
      clear_cookie(env, SESSION_COOKIE, Security::RequestSecurity.https?(env))
    end

    def self.revoke_sessions!
      @@session_mutex.synchronize { @@sessions.clear }
    end

    def self.issue_form_token(env : HTTP::Server::Context,
                              secure : Bool = Security::RequestSecurity.https?(env)) : String
      token = Random::Secure.urlsafe_base64(32)
      set_cookie(env, FORM_CSRF_COOKIE, token, secure, 15.minutes)
      token
    end

    def self.valid_form_token?(env : HTTP::Server::Context, submitted : String?) : Bool
      cookie = env.request.cookies[FORM_CSRF_COOKIE]?.try(&.value)
      !!cookie && !!submitted && Security::ConstantTime.equal?(cookie, submitted)
    end

    def self.create_mfa_challenge(env : HTTP::Server::Context, ip : String,
                                  secure : Bool = Security::RequestSecurity.https?(env),
                                  now : Time = Time.utc)
      challenge = PendingChallenge.new(ip, now)
      @@session_mutex.synchronize do
        cleanup_challenges(now)
        @@challenges[challenge.token] = challenge
      end
      set_cookie(env, MFA_CHALLENGE_COOKIE, challenge.token, secure, MFA_CHALLENGE_MAX_AGE)
    end

    def self.pending_mfa_challenge?(env : HTTP::Server::Context, ip : String,
                                    now : Time = Time.utc) : Bool
      token = env.request.cookies[MFA_CHALLENGE_COOKIE]?.try(&.value)
      return false unless token
      @@session_mutex.synchronize do
        challenge = @@challenges[token]?
        if challenge && !challenge.expired?(now) &&
           Security::ConstantTime.equal?(challenge.ip, ip)
          true
        else
          @@challenges.delete(token)
          false
        end
      end
    end

    def self.verify_mfa_challenge(env : HTTP::Server::Context, ip : String,
                                  code : String, now : Time = Time.utc) : Bool
      token = env.request.cookies[MFA_CHALLENGE_COOKIE]?.try(&.value)
      return false unless token
      challenge = @@session_mutex.synchronize { @@challenges[token]? }
      return false unless challenge &&
                          !challenge.expired?(now) &&
                          Security::ConstantTime.equal?(challenge.ip, ip)

      valid = verify_second_factor(code, now)
      @@session_mutex.synchronize do
        if valid
          @@challenges.delete(token)
        else
          challenge.attempts += 1
          @@challenges.delete(token) if challenge.expired?(now)
        end
      end
      clear_cookie(env, MFA_CHALLENGE_COOKIE, Security::RequestSecurity.https?(env)) if valid
      valid
    end

    def self.begin_enrollment(session : Session, now : Time = Time.utc) : Enrollment
      enrollment = Enrollment.new(now)
      @@session_mutex.synchronize do
        cleanup_enrollments(now)
        @@enrollments.delete(session.token).try(&.wipe!)
        @@enrollments[session.token] = enrollment
      end
      enrollment
    end

    def self.enrollment_for(session : Session, now : Time = Time.utc) : Enrollment?
      @@session_mutex.synchronize do
        enrollment = @@enrollments[session.token]?
        if enrollment.try(&.expired?(now))
          @@enrollments.delete(session.token).try(&.wipe!)
          nil
        else
          enrollment
        end
      end
    end

    def self.confirm_enrollment(env : HTTP::Server::Context, session : Session,
                                code : String,
                                secure : Bool = Security::RequestSecurity.https?(env),
                                now : Time = Time.utc) : Session?
      enrollment = enrollment_for(session, now)
      return nil unless enrollment
      step = Security::TOTP.matching_step(enrollment.secret, code, now)
      return nil unless step

      recovery_codes = generate_recovery_codes
      reference = Security::SecretStore.protect(enrollment.secret)
      data = load_data
      return nil unless data
      data.mfa = MfaState.new(
        reference,
        recovery_codes.map { |value| recovery_hash(value) },
        last_totp_step: step)
      data.generation = new_generation
      @@state_mutex.synchronize { save_data(data) }

      @@session_mutex.synchronize do
        @@enrollments.delete(session.token).try(&.wipe!)
        @@sessions.clear
      end
      new_session = create_session(env, secure, now)
      new_session.recovery_codes = recovery_codes
      new_session
    rescue
      Security::SecretStore.delete(reference) if reference
      nil
    end

    def self.verify_second_factor(code : String, now : Time = Time.utc) : Bool
      @@state_mutex.synchronize do
        data = load_data
        mfa = data.try(&.mfa)
        return false unless data && mfa

        secret = Security::SecretStore.unprotect(mfa.secret)
        if step = Security::TOTP.matching_step(secret, code, now, mfa.last_totp_step)
          mfa.last_totp_step = step
          save_data(data)
          return true
        end

        submitted_hash = recovery_hash(code)
        matched_index : Int32? = nil
        mfa.recovery_hashes.each_with_index do |stored, index|
          matched_index = index if Security::ConstantTime.equal?(stored, submitted_hash)
        end
        if index = matched_index
          mfa.recovery_hashes.delete_at(index)
          save_data(data)
          return true
        end
        false
      ensure
        secret.try(&.fill(0_u8))
      end
    rescue
      false
    end

    def self.disable_mfa!(env : HTTP::Server::Context,
                          secure : Bool = Security::RequestSecurity.https?(env),
                          now : Time = Time.utc) : Session?
      data = load_data
      mfa = data.try(&.mfa)
      return nil unless data && mfa
      Security::SecretStore.delete(mfa.secret)
      data.mfa = nil
      data.generation = new_generation
      @@state_mutex.synchronize { save_data(data) }
      clear_runtime_credentials!
      create_session(env, secure, now)
    end

    def self.regenerate_recovery_codes!(env : HTTP::Server::Context,
                                        secure : Bool = Security::RequestSecurity.https?(env),
                                        now : Time = Time.utc) : Session?
      codes = generate_recovery_codes
      data = load_data
      mfa = data.try(&.mfa)
      return nil unless data && mfa
      mfa.recovery_hashes = codes.map { |value| recovery_hash(value) }
      data.generation = new_generation
      @@state_mutex.synchronize { save_data(data) }
      clear_runtime_credentials!
      session = create_session(env, secure, now)
      session.recovery_codes = codes
      session
    end

    def self.login_limiter : Security::LoginLimiter
      @@login_limiter
    end

    def self.reset_runtime!
      clear_runtime_credentials!
      @@login_limiter.reset!
    end

    private def self.create_password_hash(password : String) : String
      digest = Digest::SHA256.digest(password)
      encoded = Base64.strict_encode(digest)
      Crypto::Bcrypt::Password.create(encoded, cost: 12).to_s
    ensure
      digest.try(&.fill(0_u8))
    end

    private def self.verify_password_hash(data : Data, password : String) : Bool
      case data.password_algorithm
      when PASSWORD_ALGORITHM
        digest = Digest::SHA256.digest(password)
        encoded = Base64.strict_encode(digest)
        Crypto::Bcrypt::Password.new(data.password_hash).verify(encoded)
      when "bcrypt"
        Crypto::Bcrypt::Password.new(data.password_hash).verify(password)
      else
        false
      end
    ensure
      digest.try(&.fill(0_u8))
    end

    private def self.upgrade_password_hash(data : Data, password : String)
      @@state_mutex.synchronize do
        latest = load_data
        return unless latest && latest.password_algorithm != PASSWORD_ALGORITHM
        latest.password_hash = create_password_hash(password)
        latest.password_algorithm = PASSWORD_ALGORITHM
        latest.version = VERSION
        save_data(latest)
      end
    end

    private def self.generate_recovery_codes : Array(String)
      Array.new(RECOVERY_CODE_COUNT) do
        Random::Secure.hex(16).upcase.scan(/.{4}/).join("-")
      end
    end

    private def self.recovery_hash(code : String) : String
      normalized = code.upcase.gsub(/[^A-Z0-9]/, "")
      Digest::SHA256.hexdigest(normalized)
    end

    private def self.new_generation : String
      Random::Secure.urlsafe_base64(32)
    end

    private def self.current_generation : String?
      load_data.try(&.generation)
    end

    private def self.load_data : Data?
      return nil unless File.exists?(Util::Paths.auth_file)
      content = File.read(Util::Paths.auth_file)
      yaml = YAML.parse(content)
      if yaml["version"]?
        Data.from_yaml(content)
      else
        hash = yaml["password_hash"]?.try(&.as_s?)
        return nil unless hash
        generation = yaml["generation"]?.try(&.as_s?) || "legacy:#{hash}"
        Data.new(hash, generation, password_algorithm: "bcrypt", version: 1)
      end
    rescue
      nil
    end

    private def self.save_data(data : Data)
      Util::AtomicFile.write(Util::Paths.auth_file, data.to_yaml, permissions: 0o600)
    end

    private def self.clear_runtime_credentials!
      @@session_mutex.synchronize do
        @@sessions.clear
        @@challenges.clear
        @@enrollments.each_value(&.wipe!)
        @@enrollments.clear
      end
    end

    private def self.cleanup_challenges(now : Time)
      @@challenges.reject! { |_token, challenge| challenge.expired?(now) }
    end

    private def self.cleanup_enrollments(now : Time)
      expired = @@enrollments.select { |_token, enrollment| enrollment.expired?(now) }
      expired.each_value(&.wipe!)
      expired.each_key { |token| @@enrollments.delete(token) }
    end

    private def self.set_cookie(env : HTTP::Server::Context, name : String,
                                value : String, secure : Bool, max_age : Time::Span)
      env.response.cookies << HTTP::Cookie.new(
        name,
        value,
        path: "/",
        secure: secure,
        http_only: true,
        samesite: HTTP::Cookie::SameSite::Strict,
        max_age: max_age
      )
    end

    private def self.clear_cookie(env : HTTP::Server::Context, name : String, secure : Bool)
      env.response.cookies << HTTP::Cookie.new(
        name,
        "",
        path: "/",
        secure: secure,
        http_only: true,
        samesite: HTTP::Cookie::SameSite::Strict,
        max_age: 0.seconds
      )
    end
  end
end
