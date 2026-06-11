require "yaml"
require "crypto/bcrypt/password"

module Patty
  # Single-admin auth. The bcrypt hash lives in auth.yml; sessions are
  # in-memory (a Patty restart logs everyone out, which is fine for v0.0).
  module Auth
    SESSION_COOKIE  = "patty_session"
    SESSION_MAX_AGE = 7.days

    class Session
      getter token : String
      getter csrf_token : String
      getter created_at : Time
      @flash : {String, String}?

      def initialize
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
      Dir.mkdir_p(Util::Paths.data_dir)
      File.write(Util::Paths.auth_file, {"password_hash" => hash}.to_yaml)
      File.chmod(Util::Paths.auth_file, 0o600)
    end

    def self.verify_password(password : String) : Bool
      return false unless password_set?
      data = YAML.parse(File.read(Util::Paths.auth_file))
      hash = data["password_hash"]?.try(&.as_s?)
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
      session = Session.new
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
      if session && session.expired?
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
  end
end
