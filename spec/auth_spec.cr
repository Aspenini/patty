require "./spec_helper"

private def auth_context(session_token : String? = nil) : HTTP::Server::Context
  headers = HTTP::Headers.new
  headers["Cookie"] = "#{Patty::Auth::SESSION_COOKIE}=#{session_token}" if session_token
  request = HTTP::Request.new("GET", "/", headers)
  response = HTTP::Server::Response.new(IO::Memory.new)
  HTTP::Server::Context.new(request, response)
end

describe Patty::Auth do
  it "invalidates sessions when the credential generation changes externally" do
    fresh_home!
    Patty::Auth.set_password("old-password")
    session = Patty::Auth.create_session(auth_context)
    Patty::Auth.session_for(auth_context(session.token)).should_not be_nil

    data = YAML.parse(File.read(Patty::Util::Paths.auth_file))
    replacement = {
      "password_hash" => data["password_hash"].as_s,
      "generation"    => Random::Secure.urlsafe_base64(32),
    }
    Patty::Util::AtomicFile.write(Patty::Util::Paths.auth_file, replacement.to_yaml, permissions: 0o600)

    Patty::Auth.session_for(auth_context(session.token)).should be_nil
  end

  it "authenticates legacy credential files without a generation" do
    fresh_home!
    Patty::Auth.set_password("legacy-password")
    data = YAML.parse(File.read(Patty::Util::Paths.auth_file))
    legacy = {"password_hash" => data["password_hash"].as_s}
    Patty::Util::AtomicFile.write(Patty::Util::Paths.auth_file, legacy.to_yaml, permissions: 0o600)

    Patty::Auth.verify_password("legacy-password").should be_true
    session = Patty::Auth.create_session(auth_context)
    Patty::Auth.session_for(auth_context(session.token)).should_not be_nil
  end
end
