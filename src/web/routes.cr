require "json"

# All HTTP routes. Pages render server-side via ECR; actions are plain form
# POSTs that flash a Result and redirect (spec §8).

STYLE_CSS = {{ read_file("#{__DIR__}/static/style.css") }}
APP_JS    = {{ read_file("#{__DIR__}/static/app.js") }}
ICON_PNG  = {{ read_file("#{__DIR__}/../../icons/icon.png") }}

macro page(name)
  render "src/web/pages/{{name.id}}.ecr", "src/web/pages/layout.ecr"
end

macro bare_page(name)
  render "src/web/pages/{{name.id}}.ecr"
end

def dashboard_browser_url(config : Patty::Config) : String?
  address = config.caddy.dashboard_address
  address ? Patty::Caddy::DashboardAddress.browser_url(address) : nil
rescue ArgumentError
  nil
end

# --- auth gate -------------------------------------------------------------

before_all do |env|
  next if env.response.closed?

  path = env.request.path
  next if path.starts_with?("/static/")

  unless Patty::Auth.password_set?
    env.redirect "/setup" unless path == "/setup"
    next
  end

  if path == "/setup"
    env.redirect "/"
    next
  end
  next if path == "/login"

  session = Patty::Auth.session_for(env)
  unless session
    env.redirect "/login"
    next
  end

  if env.request.method == "POST"
    token = env.params.body["csrf_token"]?
    unless token && token == session.csrf_token
      halt env, status_code: 403, response: "CSRF token mismatch. Go back, reload the page, and try again."
    end
  end
end

# --- static assets (compiled into the binary) ------------------------------

get "/static/style.css" do |env|
  env.response.content_type = "text/css"
  STYLE_CSS
end

get "/static/app.js" do |env|
  env.response.content_type = "application/javascript"
  APP_JS
end

# --- first-run setup & login ------------------------------------------------

get "/setup" do |env|
  error = nil
  bare_page(:setup)
end

post "/setup" do |env|
  password = env.params.body["password"]?.to_s
  confirm = env.params.body["password_confirm"]?.to_s
  error =
    if password.size < 8
      "Password must be at least 8 characters."
    elsif password != confirm
      "Passwords do not match."
    end
  if error
    bare_page(:setup)
  else
    Patty::Auth.set_password(password)
    Patty::Util::ActionLog.log("Admin password set via first-run setup.")
    Patty::Auth.create_session(env)
    env.redirect "/"
  end
end

get "/login" do |env|
  error = nil
  bare_page(:login)
end

post "/login" do |env|
  password = env.params.body["password"]?.to_s
  if Patty::Auth.verify_password(password)
    Patty::Auth.create_session(env)
    env.redirect "/"
  else
    Patty::Util::ActionLog.log("Failed login attempt.")
    error = "Wrong password."
    bare_page(:login)
  end
end

post "/logout" do |env|
  Patty::Auth.destroy_session(env)
  env.redirect "/login"
end

# --- dashboard ---------------------------------------------------------------

get "/" do |env|
  session = Patty::Auth.session_for(env).not_nil!
  csrf = session.csrf_token
  flash = session.take_flash
  snapshot = Patty::Core::State.snapshot
  page(:dashboard)
end

# --- profile CRUD ------------------------------------------------------------

get "/profiles/new" do |env|
  session = Patty::Auth.session_for(env).not_nil!
  csrf = session.csrf_token
  flash = session.take_flash
  editing = false
  form_action = "/profiles"
  errors = [] of String
  v = {} of String => String
  page(:profile_form)
end

post "/profiles" do |env|
  session = Patty::Auth.session_for(env).not_nil!
  csrf = session.csrf_token
  flash = nil
  editing = false
  form_action = "/profiles"

  v = form_values(env)
  profile = profile_from_form(v, id: v["id"]?.try(&.strip.presence))
  errors = Patty::Profiles::Validator.validate(profile)
  errors << "filename must not be empty" unless profile.id
  if (custom_id = profile.id) && Patty::Profiles::Store.exists?(custom_id)
    errors << "a Pattyfile named \"#{custom_id}.pattyfile\" already exists"
  end

  if errors.empty?
    saved = Patty::Profiles::Store.save(profile)
    Patty::Util::ActionLog.log("Created profile #{saved.slug}.")
    session.flash!("success", "Profile #{saved.name} created.")
    env.redirect "/profiles/#{saved.slug}"
  else
    page(:profile_form)
  end
end

get "/profiles/:id" do |env|
  session = Patty::Auth.session_for(env).not_nil!
  csrf = session.csrf_token
  flash = session.take_flash
  profile = Patty::Profiles::Store.find(env.params.url["id"])
  if profile
    status = profile_status(profile)
    page(:profile_detail)
  else
    halt env, status_code: 404, response: "Profile not found"
  end
end

get "/profiles/:id/edit" do |env|
  session = Patty::Auth.session_for(env).not_nil!
  csrf = session.csrf_token
  flash = session.take_flash
  profile = Patty::Profiles::Store.find(env.params.url["id"])
  if profile
    editing = true
    form_action = "/profiles/#{profile.slug}"
    errors = [] of String
    v = {
      "program" => profile.program.to_s,
      "caddy"   => profile.caddy,
      "id"      => profile.slug,
    }
    page(:profile_form)
  else
    halt env, status_code: 404, response: "Profile not found"
  end
end

post "/profiles/:id" do |env|
  session = Patty::Auth.session_for(env).not_nil!
  csrf = session.csrf_token
  flash = nil
  existing = Patty::Profiles::Store.find(env.params.url["id"])
  unless existing
    halt env, status_code: 404, response: "Profile not found"
  end

  editing = true
  form_action = "/profiles/#{existing.slug}"
  v = form_values(env)
  v["id"] = existing.slug
  profile = profile_from_form(v, id: existing.slug)
  errors = Patty::Profiles::Validator.validate(profile)

  if errors.empty?
    result = Patty::Core::Actions.update_profile(existing.slug, profile)
    if result.ok?
      session.flash(result)
      env.redirect "/profiles/#{profile.slug}"
    else
      errors << result.message
      if detail = result.detail
        errors << detail
      end
      page(:profile_form)
    end
  else
    page(:profile_form)
  end
end

post "/profiles/:id/delete" do |env|
  session = Patty::Auth.session_for(env).not_nil!
  result = Patty::Core::Actions.delete_profile(env.params.url["id"])
  session.flash(result)
  env.redirect "/"
end

get "/profiles/:id/export" do |env|
  profile = Patty::Profiles::Store.find(env.params.url["id"])
  if profile
    env.response.content_type = "application/x-yaml"
    env.response.headers["Content-Disposition"] = %(attachment; filename="#{profile.slug}.pattyfile")
    profile.to_pattyfile
  else
    halt env, status_code: 404, response: "Profile not found"
  end
end

# --- import ------------------------------------------------------------------

get "/import" do |env|
  session = Patty::Auth.session_for(env).not_nil!
  csrf = session.csrf_token
  flash = session.take_flash
  import_error = nil
  page(:import)
end

post "/import" do |env|
  session = Patty::Auth.session_for(env).not_nil!
  csrf = session.csrf_token
  flash = nil
  import_error = nil

  upload = env.params.files["pattyfile"]?
  if upload.nil?
    import_error = "No file was uploaded."
    next page(:import)
  end

  content = File.read(upload.tempfile.path)
  begin
    filename = upload.filename || "profile.pattyfile"
    unless filename.downcase.ends_with?(".pattyfile")
      import_error = "Choose a file ending in .pattyfile."
      next page(:import)
    end

    preview = Patty::Profiles::Parser.parse(content)
    validation = Patty::Profiles::Validator.validate(preview)
    unless validation.empty?
      import_error = "This .pattyfile is not valid:\n" + validation.join("\n")
      next page(:import)
    end
    final_id = import_id_for(filename)
    preview.id = final_id
    page(:import_preview)
  rescue ex : Patty::Profiles::ParseError
    import_error = "Could not parse the file: #{ex.message}"
    page(:import)
  end
end

post "/import/confirm" do |env|
  session = Patty::Auth.session_for(env).not_nil!
  content = env.params.body["content"]?.to_s
  requested_id = env.params.body["id"]?.to_s
  begin
    profile = Patty::Profiles::Parser.parse(content)
    validation = Patty::Profiles::Validator.validate(profile)
    unless validation.empty?
      session.flash!("error", "Import failed:\n" + validation.join("\n"))
      next env.redirect "/import"
    end
    profile.id = import_id_for(requested_id)
    saved = Patty::Profiles::Store.save(profile)
    Patty::Util::ActionLog.log("Imported profile #{saved.slug}.")
    session.flash!("success", "Imported #{saved.name} as #{saved.slug}.")
    env.redirect "/profiles/#{saved.slug}"
  rescue ex : Patty::Profiles::ParseError
    session.flash!("error", "Import failed: #{ex.message}")
    env.redirect "/import"
  end
end

# --- actions -----------------------------------------------------------------

post "/profiles/:id/start" do |env|
  run_action(env) { |id| Patty::Core::Actions.start_profile(id) }
end

post "/profiles/:id/stop" do |env|
  run_action(env) { |id| Patty::Core::Actions.stop_profile(id) }
end

post "/profiles/:id/restart" do |env|
  run_action(env) { |id| Patty::Core::Actions.restart_profile(id) }
end

post "/caddy/validate" do |env|
  session = Patty::Auth.session_for(env).not_nil!
  session.flash(Patty::Core::Actions.validate_caddy)
  env.redirect(env.request.headers["Referer"]? || "/")
end

post "/caddy/reload" do |env|
  session = Patty::Auth.session_for(env).not_nil!
  session.flash(Patty::Core::Actions.reload_caddy)
  env.redirect(env.request.headers["Referer"]? || "/")
end

# --- settings ----------------------------------------------------------------

get "/settings" do |env|
  session = Patty::Auth.session_for(env).not_nil!
  csrf = session.csrf_token
  flash = session.take_flash
  config = Patty::Config.instance
  errors = [] of String
  autostart = Patty::Install::Autostart.installed?
  page(:settings)
end

get "/static/icon.png" do |env|
  env.response.content_type = "image/png"
  env.response.headers["Cache-Control"] = "public, max-age=86400"
  ICON_PNG
end

post "/settings" do |env|
  session = Patty::Auth.session_for(env).not_nil!
  previous_yaml = Patty::Config.instance.to_yaml
  config = Patty::Config.from_yaml(previous_yaml)
  config.server.bind = env.params.body["bind"]?.to_s.strip.presence || "127.0.0.1"
  config.server.port = env.params.body["port"]?.to_s.to_i? || 7629
  config.caddy.binary = env.params.body["caddy_binary"]?.to_s.strip.presence || "caddy"
  config.caddy.dashboard_address = env.params.body["dashboard_address"]?.to_s.strip.presence
  config.caddy.validate_before_reload = env.params.body["validate_before_reload"]? == "on"
  config.caddy.reload_after_apply = env.params.body["reload_after_apply"]? == "on"
  errors = config.errors
  if errors.empty?
    config.caddy.dashboard_address = Patty::Caddy::DashboardAddress.normalize(config.caddy.dashboard_address)
    config.save
    Patty::Config.reload!
    route = Patty::Caddy::Manager.configure_dashboard(config)
    if route.ok?
      Patty::Util::ActionLog.log("Settings saved. #{route.message}")
      session.flash!("success", "Settings saved. #{route.message} Server changes apply after restarting Patty.")
      env.redirect "/settings"
    else
      Patty::Config.from_yaml(previous_yaml).save
      Patty::Config.reload!
      errors << route.message
      errors << route.detail.not_nil! if route.detail
      flash = nil
      csrf = session.csrf_token
      autostart = Patty::Install::Autostart.installed?
      page(:settings)
    end
  else
    flash = nil
    csrf = session.csrf_token
    autostart = Patty::Install::Autostart.installed?
    page(:settings)
  end
end

post "/settings/autostart/install" do |env|
  session = Patty::Auth.session_for(env).not_nil!
  session.flash(Patty::Install::Autostart.install)
  env.redirect "/settings"
end

post "/settings/autostart/uninstall" do |env|
  session = Patty::Auth.session_for(env).not_nil!
  session.flash(Patty::Install::Autostart.uninstall)
  env.redirect "/settings"
end

# --- logs --------------------------------------------------------------------

get "/logs" do |env|
  session = Patty::Auth.session_for(env).not_nil!
  csrf = session.csrf_token
  flash = session.take_flash
  patty_lines = Patty::Util::ActionLog.tail
  caddy_lines = Patty::Util::ActionLog.tail_file(Patty::Util::Paths.caddy_log_file)
  page(:logs)
end

# --- status API (used by app.js polling) --------------------------------------

get "/api/status" do |env|
  env.response.content_type = "application/json"
  snapshot = Patty::Core::State.snapshot
  JSON.build do |json|
    json.object do
      json.field "caddy" do
        json.object do
          json.field "found", snapshot.caddy_found
          json.field "running", snapshot.caddy_running
        end
      end
      json.field "profiles" do
        json.array do
          snapshot.profiles.each do |p|
            json.object do
              json.field "id", p.id
              json.field "service", p.service.try(&.label)
              json.field "route_enabled", p.route_enabled
              json.field "health", p.health.state.label
              json.field "health_label", p.health.label
              json.field "health_detail", p.health.detail
              json.field "warnings", p.warnings
            end
          end
        end
      end
    end
  end
end

# --- route helpers -------------------------------------------------------------

private def run_action(env, & : String -> Patty::Result)
  session = Patty::Auth.session_for(env).not_nil!
  result = yield env.params.url["id"]
  session.flash(result)
  env.redirect(env.request.headers["Referer"]? || "/")
end

private def form_values(env) : Hash(String, String)
  values = {} of String => String
  {"program", "caddy", "id"}.each do |key|
    values[key] = env.params.body[key]?.to_s.gsub("\r\n", "\n")
  end
  values
end

private def profile_from_form(v : Hash(String, String), id : String?) : Patty::Profile
  Patty::Profile.new(
    caddy: v["caddy"],
    program: v["program"].strip.presence,
    id: id,
  )
end

private def profile_status(profile : Patty::Profile) : Patty::Core::State::ProfileStatus
  Patty::Core::State.profile_status(profile)
end

# Derives a safe identity from the uploaded filename and avoids collisions.
private def import_id_for(filename : String) : String
  existing = Patty::Profiles::Store.ids
  basename = File.basename(filename)
  stem = File.basename(basename, File.extname(basename))
  Patty::Profiles::IdGenerator.generate(stem, existing)
end
