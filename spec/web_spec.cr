require "./spec_helper"
require "kemal"
require "http/formdata"
require "../src/core/state"
require "../src/web/render"
require "../src/web/routes"

private def patty_request(method : String, path : String, body : String? = nil,
                          cookie : String? = nil,
                          content_type = "application/x-www-form-urlencoded",
                          request_headers : HTTP::Headers? = nil,
                          remote_ip : String? = nil) : HTTP::Client::Response
  headers = HTTP::Headers.new
  if body
    headers["Content-Type"] = content_type
    headers["Content-Length"] = body.bytesize.to_s
  end
  headers["Cookie"] = cookie if cookie
  request_headers.try &.each { |key, value| headers[key] = value }
  request = HTTP::Request.new(method, path, headers, body)
  request.remote_address = Socket::IPAddress.new(remote_ip, 0) if remote_ip

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

private def auth_form(path : String = "/login") : {String, String}
  response = patty_request("GET", path)
  token = response.body.match(/name="csrf_token" value="([^"]+)"/).not_nil![1]
  cookie = response.headers["Set-Cookie"].split(';').first
  {token, cookie}
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

  it "requires a pre-session CSRF token for login" do
    fresh_home!
    Patty::Auth.set_password("configured-password")

    response = patty_request("POST", "/login", "password=configured-password")

    response.status_code.should eq 403
    response.body.should contain "CSRF"
  end

  it "logs in with valid credentials and sets a session cookie" do
    fresh_home!
    Patty::Auth.set_password("configured-password")
    csrf, form_cookie = auth_form

    body = URI::Params.encode({
      "csrf_token" => csrf,
      "password"   => "configured-password",
    })
    response = patty_request("POST", "/login", body, form_cookie)

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

  it "sets defensive headers and rejects cross-origin posts" do
    fresh_home!
    Patty::Auth.set_password("configured-password")
    session = web_session
    cookie = "#{Patty::Auth::SESSION_COOKIE}=#{session.token}"

    get_response = patty_request("GET", "/", cookie: cookie)
    get_response.headers["Content-Security-Policy"].should contain "frame-ancestors 'none'"
    get_response.headers["X-Content-Type-Options"].should eq "nosniff"
    get_response.headers["Cache-Control"].should eq "no-store"
    get_response.headers["Referrer-Policy"].should eq "same-origin"

    headers = HTTP::Headers{
      "Host"   => "patty.example.com",
      "Origin" => "https://evil.example",
    }
    body = URI::Params.encode({"csrf_token" => session.csrf_token})
    post_response = patty_request(
      "POST", "/logout", body, cookie, request_headers: headers)
    post_response.status_code.should eq 403
    post_response.body.should contain "origin"

    local_session = web_session
    local_cookie = "#{Patty::Auth::SESSION_COOKIE}=#{local_session.token}"
    local_headers = HTTP::Headers{
      "Host"   => "127.0.0.1:7629",
      "Origin" => "null",
    }
    local_body = URI::Params.encode({"csrf_token" => local_session.csrf_token})
    local_response = patty_request(
      "POST", "/logout", local_body, local_cookie,
      request_headers: local_headers, remote_ip: "127.0.0.1")
    local_response.status_code.should eq 302

    proxy_session = web_session
    proxy_cookie = "#{Patty::Auth::SESSION_COOKIE}=#{proxy_session.token}"
    proxy_headers = HTTP::Headers{
      "Host"              => "127.0.0.1:7629",
      "Origin"            => "null",
      "X-Forwarded-Host"  => "patty.example.com",
      "X-Forwarded-Proto" => "https",
      "X-Forwarded-For"   => "192.168.50.1",
    }
    proxy_body = URI::Params.encode({"csrf_token" => proxy_session.csrf_token})
    proxy_response = patty_request(
      "POST", "/logout", proxy_body, proxy_cookie,
      request_headers: proxy_headers, remote_ip: "127.0.0.1")
    proxy_response.status_code.should eq 302
  end

  it "uses Secure strict cookies only for trusted HTTPS proxy requests" do
    fresh_home!
    Patty::Auth.set_password("configured-password")
    headers = HTTP::Headers{
      "Host"              => "patty.example.com",
      "X-Forwarded-Proto" => "https",
      "X-Forwarded-For"   => "203.0.113.10",
    }
    csrf_response = patty_request(
      "GET", "/login", request_headers: headers, remote_ip: "127.0.0.1")
    csrf_response.headers["Set-Cookie"].should contain "Secure"
    csrf_response.headers["Set-Cookie"].should contain "SameSite=Strict"
    csrf_response.headers["Strict-Transport-Security"].should contain "max-age"

    spoofed = patty_request(
      "GET", "/login", request_headers: headers, remote_ip: "203.0.113.20")
    spoofed.headers["Set-Cookie"].should_not contain "Secure"
    spoofed.headers.has_key?("Strict-Transport-Security").should be_false
  end

  it "requires MFA after a valid password when enabled" do
    fresh_home!
    Patty::Auth.set_password("configured-password")
    now = Time.utc
    session = web_session
    enrollment = Patty::Auth.begin_enrollment(session, now)
    code = Patty::Security::TOTP.code(enrollment.secret, now)
    Patty::Auth.confirm_enrollment(
      web_context_with_cookie(""),
      session,
      code,
      secure: false,
      now: now).should_not be_nil

    csrf, form_cookie = auth_form
    body = URI::Params.encode({
      "csrf_token" => csrf,
      "password"   => "configured-password",
    })
    response = patty_request("POST", "/login", body, form_cookie)

    response.status_code.should eq 302
    response.headers["Location"].should eq "/login/mfa"
    response.headers["Set-Cookie"].should contain Patty::Auth::MFA_CHALLENGE_COOKIE
    response.headers["Set-Cookie"].should_not contain Patty::Auth::SESSION_COOKIE
  end
end

describe "minimal Pattyfile web UI" do
  it "creates a Caddy-only profile using the required filename" do
    fresh_home!
    Patty::Auth.set_password("configured-password")
    session = web_session
    cookie = "#{Patty::Auth::SESSION_COOKIE}=#{session.token}"
    body = URI::Params.encode({
      "csrf_token" => session.csrf_token,
      "id"         => "static-files",
      "program"    => "",
      "caddy"      => "files.localhost {\n    file_server\n}\n",
    })

    response = patty_request("POST", "/profiles", body, cookie)

    response.status_code.should eq 302
    response.headers["Location"].should eq "/profiles/static-files"
    stored = Patty::Profiles::Store.find("static-files").not_nil!
    stored.program.should be_nil
    stored.to_pattyfile.should_not contain "program:"
  end

  it "derives import identity from the uploaded filename and resolves collisions" do
    fresh_home!
    Patty::Auth.set_password("configured-password")
    session = web_session
    cookie = "#{Patty::Auth::SESSION_COOKIE}=#{session.token}"
    Patty::Profiles::Store.save(Patty::Profile.new(
      caddy: "existing.localhost {\n    respond \"existing\"\n}\n",
      id: "my-files"))
    content = "caddy: |\n  files.localhost {\n      file_server\n  }\n"

    io = IO::Memory.new
    form = HTTP::FormData::Builder.new(io)
    form.field("csrf_token", session.csrf_token)
    form.file(
      "pattyfile",
      IO::Memory.new(content),
      HTTP::FormData::FileMetadata.new(filename: "My Files.pattyfile"))
    form.finish

    preview = patty_request("POST", "/import", io.to_s, cookie, form.content_type)

    preview.status_code.should eq 200
    preview.body.should contain "my-files-2.pattyfile"

    confirm_body = URI::Params.encode({
      "csrf_token" => session.csrf_token,
      "content"    => content,
      "id"         => "my-files-2",
    })
    confirmed = patty_request("POST", "/import/confirm", confirm_body, cookie)

    confirmed.status_code.should eq 302
    confirmed.headers["Location"].should eq "/profiles/my-files-2"
    Patty::Profiles::Store.find("my-files-2").should_not be_nil
  end

  it "renders lifecycle controls from route state and hides service UI for Caddy-only profiles" do
    fresh_home!
    Patty::Auth.set_password("configured-password")
    session = web_session
    cookie = "#{Patty::Auth::SESSION_COOKIE}=#{session.token}"

    caddy_only = Patty::Profile.new(
      caddy: "files.localhost {\n    root * /srv/files\n    file_server\n}\n",
      id: "static-files")
    program = Patty::Profile.new(
      caddy: "app.localhost {\n    reverse_proxy 127.0.0.1:3000\n}\n",
      program: "my-app",
      id: "my-app")
    Patty::Profiles::Store.save(caddy_only)
    Patty::Profiles::Store.save(program)
    Patty::Caddy::Snippets.write(caddy_only.slug, Patty::Caddy::Snippets.render(caddy_only))
    Patty::Services::Manager.adapters = [
      FakeServiceAdapter.new(Patty::Services::Status::Stopped),
    ] of Patty::Services::Adapter

    dashboard = patty_request("GET", "/", cookie: cookie)
    dashboard.status_code.should eq 200
    dashboard.body.should contain "Caddy only"
    dashboard.body.should contain "/profiles/static-files/stop"
    dashboard.body.should contain "/profiles/my-app/start"
    dashboard.body.should_not contain "enable-route"
    dashboard.body.should_not contain "disable-route"

    caddy_detail = patty_request("GET", "/profiles/static-files", cookie: cookie)
    caddy_detail.body.should contain "static-files.pattyfile"
    caddy_detail.body.should_not contain "/profiles/static-files/restart"

    program_detail = patty_request("GET", "/profiles/my-app", cookie: cookie)
    program_detail.body.should contain "/profiles/my-app/restart"
  end

  it "returns null service status for Caddy-only profiles" do
    fresh_home!
    Patty::Auth.set_password("configured-password")
    session = web_session
    cookie = "#{Patty::Auth::SESSION_COOKIE}=#{session.token}"

    Patty::Profiles::Store.save(Patty::Profile.new(
      caddy: "files.localhost {\n    file_server\n}\n",
      id: "static-files"))
    Patty::Profiles::Store.save(Patty::Profile.new(
      caddy: "app.localhost {\n    reverse_proxy 127.0.0.1:3000\n}\n",
      program: "my-app",
      id: "my-app"))
    Patty::Services::Manager.adapters = [
      FakeServiceAdapter.new(Patty::Services::Status::Running),
    ] of Patty::Services::Adapter

    response = patty_request("GET", "/api/status", cookie: cookie)
    response.status_code.should eq 200
    profiles = JSON.parse(response.body)["profiles"].as_a
    caddy_only = profiles.find { |profile| profile["id"].as_s == "static-files" }.not_nil!
    program = profiles.find { |profile| profile["id"].as_s == "my-app" }.not_nil!

    caddy_only["service"].raw.should be_nil
    program["service"].as_s.should eq "running"
  end

  it "shows both Patty and Caddy logs" do
    fresh_home!
    Patty::Auth.set_password("configured-password")
    session = web_session
    cookie = "#{Patty::Auth::SESSION_COOKIE}=#{session.token}"
    Patty::Util::ActionLog.log("Patty log marker")
    File.write(Patty::Util::Paths.caddy_log_file, "Caddy log marker\n")

    response = patty_request("GET", "/logs", cookie: cookie)

    response.status_code.should eq 200
    response.body.should contain "Patty log marker"
    response.body.should contain "Caddy log marker"
  end

  it "rejects invalid settings without mutating the active config" do
    fresh_home!
    Patty::Auth.set_password("configured-password")
    session = web_session
    cookie = "#{Patty::Auth::SESSION_COOKIE}=#{session.token}"
    original_port = Patty::Config.instance.server.port
    body = URI::Params.encode({
      "csrf_token"   => session.csrf_token,
      "bind"         => "127.0.0.1",
      "port"         => "0",
      "caddy_binary" => "caddy",
    })

    response = patty_request("POST", "/settings", body, cookie)

    response.status_code.should eq 200
    response.body.should contain "port must be between 1 and 65535"
    Patty::Config.instance.server.port.should eq original_port
  end

  it "creates a managed Caddy route for the dashboard from settings" do
    fresh_home!
    Patty::Auth.set_password("configured-password")
    Patty::Caddy.runtime = FakeCaddyRuntime.new
    session = web_session
    cookie = "#{Patty::Auth::SESSION_COOKIE}=#{session.token}"
    body = URI::Params.encode({
      "csrf_token"             => session.csrf_token,
      "bind"                   => "127.0.0.1",
      "port"                   => "7629",
      "caddy_binary"           => "caddy",
      "dashboard_address"      => "https://patty.example.com/",
      "validate_before_reload" => "on",
      "reload_after_apply"     => "on",
    })

    response = patty_request("POST", "/settings", body, cookie)

    response.status_code.should eq 302
    Patty::Config.instance.caddy.dashboard_address.should eq "https://patty.example.com"
    route = Patty::Caddy::Snippets.path_for(Patty::Caddy::DashboardRoute::ID)
    File.read(route).should contain "https://patty.example.com {"
    File.read(route).should contain "reverse_proxy 127.0.0.1:7629"
  end

  it "rejects dashboard addresses with paths" do
    fresh_home!
    Patty::Auth.set_password("configured-password")
    session = web_session
    cookie = "#{Patty::Auth::SESSION_COOKIE}=#{session.token}"
    body = URI::Params.encode({
      "csrf_token"        => session.csrf_token,
      "bind"              => "127.0.0.1",
      "port"              => "7629",
      "caddy_binary"      => "caddy",
      "dashboard_address" => "https://patty.example.com/private",
    })

    response = patty_request("POST", "/settings", body, cookie)

    response.status_code.should eq 200
    response.body.should contain "without a path"
    Patty::Config.instance.caddy.dashboard_address.should be_nil
  end
end
