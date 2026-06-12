require "yaml"
require "crypto/bcrypt/password"

module Patty
  # Single-admin auth. The bcrypt hash lives in auth.yml; sessions are
  # in-memory, so a Patty restart logs everyone out.
  module Auth
    SESSION_COOKIE  = "patty_session"
    SESSION_MAX_AGE = 7.days

    class Session
      getter token : String
      getter csrf_token : String
      getter created_at : Time
      getter credential_generation : String
      @flash : {String, String}?

      def initialize(@credential_generation : String)
        @token = Random::Secure.urlsafe_base64(32)
        @csrf_token = Random::Secure.urlsafe_base64(32)
        @created_at = Time.utc
      end

      def expired? : Bool
        (Time.utc - created_at) > SESSION_MAX_AGE
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
    end

    @@sessions = {} of String => Session
    @@mutex = Mutex.new

    def self.password_set? : Bool
      File.exists?(Util::Paths.auth_file)
    end

    def self.set_password(password : String)
      hash = Crypto::Bcrypt::Password.create(password, cost: 12).to_s
      generation = Random::Secure.urlsafe_base64(32)
      Util::AtomicFile.write(
        Util::Paths.auth_file,
        {"password_hash" => hash, "generation" => generation}.to_yaml,
        permissions: 0o600)
      @@mutex.synchronize { @@sessions.clear }
    end

    def self.verify_password(password : String) : Bool
      hash = credentials.try(&.[0])
      return false unless hash
      Crypto::Bcrypt::Password.new(hash).verify(password)
    rescue
      false
    end

    def self.reset_password!
      File.delete(Util::Paths.auth_file) if File.exists?(Util::Paths.auth_file)
      @@mutex.synchronize { @@sessions.clear }
    end

    def self.create_session(env) : Session
      generation = current_generation
      raise "Cannot create a session without configured credentials" unless generation
      session = Session.new(generation)
      @@mutex.synchronize { @@sessions[session.token] = session }
      env.response.cookies << HTTP::Cookie.new(
        SESSION_COOKIE, session.token,
        path: "/", http_only: true, samesite: HTTP::Cookie::SameSite::Lax)
      session
    end

    def self.session_for(env) : Session?
      token = env.request.cookies[SESSION_COOKIE]?.try(&.value)
      return nil unless token
      session = @@mutex.synchronize { @@sessions[token]? }
      generation = current_generation
      if session && (session.expired? || generation.nil? || session.credential_generation != generation)
        @@mutex.synchronize { @@sessions.delete(token) }
        return nil
      end
      session
    end

    def self.destroy_session(env)
      if token = env.request.cookies[SESSION_COOKIE]?.try(&.value)
        @@mutex.synchronize { @@sessions.delete(token) }
      end
      env.response.cookies << HTTP::Cookie.new(SESSION_COOKIE, "", path: "/", max_age: 0.seconds)
    end

    private def self.current_generation : String?
      credentials.try(&.[1])
    end

    # Legacy auth files did not have a generation. The password hash is stable
    # and changes whenever credentials are replaced, so it is a safe fallback.
    private def self.credentials : {String, String}?
      return nil unless password_set?
      data = YAML.parse(File.read(Util::Paths.auth_file))
      hash = data["password_hash"]?.try(&.as_s?)
      return nil unless hash
      generation = data["generation"]?.try(&.as_s?) || "legacy:#{hash}"
      {hash, generation}
    rescue
      nil
    end
  end
end
