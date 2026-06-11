require "./spec_helper"
require "kemal"
require "../src/core/state"
require "../src/web/render"
require "../src/web/routes"

private def patty_request(method : String, path : String, body : String? = nil,
                          cookie : String? = nil) : HTTP::Client::Response
  headers = HTTP::Headers.new
  if body
    headers["Content-Type"] = "application/x-www-form-urlencoded"
    headers["Content-Length"] = body.bytesize.to_s
  end
  headers["Cookie"] = cookie if cookie
  request = HTTP::Request.new(method, path, headers, body)

  Kemal.config.env = "test"
  Kemal.config.logging = false
  Kemal.config.setup
  handlers = Kemal.config.handlers
  current = handlers.first
  handlers.skip(1).each do |following|
    current.next = following
    current = following
  end

  io = IO::Memory.new
  response = HTTP::Server::Response.new(io)
  handlers.first.call(HTTP::Server::Context.new(request, response))
  response.close unless response.closed?
  io.rewind
  HTTP::Client::Response.from_io(io, decompress: false)
end

private def web_session : Patty::Auth::Session
  request = HTTP::Request.new("GET", "/")
  response = HTTP::Server::Response.new(IO::Memory.new)
  context = HTTP::Server::Context.new(request, response)
  Patty::Auth.create_session(context)
end

private def web_context_with_cookie(cookie : String) : HTTP::Server::Context
  request = HTTP::Request.new("GET", "/", HTTP::Headers{"Cookie" => cookie})
  HTTP::Server::Context.new(request, HTTP::Server::Response.new(IO::Memory.new))
end

describe "Patty web authentication" do
  it "redirects first-run requests to setup without a closed response error" do
    fresh_home!

    response = patty_request("GET", "/")

    response.status_code.should eq 302
    response.headers["Location"].should eq "/setup"
  end

  it "redirects unauthenticated configured requests to login" do
    fresh_home!
    Patty::Auth.set_password("configured-password")

    response = patty_request("GET", "/")

    response.status_code.should eq 302
    response.headers["Location"].should eq "/login"
  end

  it "logs in with valid credentials and sets a session cookie" do
    fresh_home!
    Patty::Auth.set_password("configured-password")

    response = patty_request("POST", "/login", "password=configured-password")

    response.status_code.should eq 302
    response.headers["Location"].should eq "/"
    response.headers.get?("Set-Cookie").to_s.should contain Patty::Auth::SESSION_COOKIE
  end

  it "rejects authenticated posts without a matching CSRF token" do
    fresh_home!
    Patty::Auth.set_password("configured-password")
    session = web_session
    cookie = "#{Patty::Auth::SESSION_COOKIE}=#{session.token}"

    response = patty_request("POST", "/logout", "", cookie)

    response.status_code.should eq 403
    response.body.should contain "CSRF token mismatch"
  end

  it "logs out with a matching CSRF token" do
    fresh_home!
    Patty::Auth.set_password("configured-password")
    session = web_session
    cookie = "#{Patty::Auth::SESSION_COOKIE}=#{session.token}"

    response = patty_request("POST", "/logout", "csrf_token=#{session.csrf_token}", cookie)

    response.status_code.should eq 302
    response.headers["Location"].should eq "/login"
    Patty::Auth.session_for(web_context_with_cookie(cookie)).should be_nil
  end
end
