require "json"

# All HTTP routes. Pages render server-side via ECR; actions are plain form
# POSTs that flash a Result and redirect (spec §8).

STYLE_CSS = {{ read_file("#{__DIR__}/static/style.css") }}
APP_JS    = {{ read_file("#{__DIR__}/static/app.js") }}

macro page(name)
  render "src/web/pages/{{name.id}}.ecr", "src/web/pages/layout.ecr"
end

macro bare_page(name)
  render "src/web/pages/{{name.id}}.ecr"
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
  profile = profile_from_form(v, id: v["id"]?.presence)
  errors = Patty::Profiles::Validator.validate(profile)
  if (custom_id = profile.id) && Patty::Profiles::Store.exists?(custom_id)
    errors << "a profile with id \"#{custom_id}\" already exists"
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
      "name"        => profile.name,
      "program"     => profile.program,
      "caddy"       => profile.caddy,
      "description" => profile.description.to_s,
      "category"    => profile.category.to_s,
      "id"          => profile.slug,
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
    preview = Patty::Profiles::Parser.parse(content)
    validation = Patty::Profiles::Validator.validate(preview)
    unless validation.empty?
      import_error = "This .pattyfile is not valid:\n" + validation.join("\n")
      next page(:import)
    end
    final_id = import_id_for(preview)
    page(:import_preview)
  rescue ex : Patty::Profiles::ParseError
    import_error = "Could not parse the file: #{ex.message}"
    page(:import)
  end
end

post "/import/confirm" do |env|
  session = Patty::Auth.session_for(env).not_nil!
  content = env.params.body["content"]?.to_s
  begin
    profile = Patty::Profiles::Parser.parse(content)
    validation = Patty::Profiles::Validator.validate(profile)
    unless validation.empty?
      session.flash!("error", "Import failed:\n" + validation.join("\n"))
      next env.redirect "/import"
    end
    profile.id = import_id_for(profile)
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

post "/profiles/:id/enable-route" do |env|
  run_action(env) { |id| Patty::Core::Actions.enable_route(id) }
end

post "/profiles/:id/disable-route" do |env|
  run_action(env) { |id| Patty::Core::Actions.disable_route(id) }
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
  page(:settings)
end

post "/settings" do |env|
  session = Patty::Auth.session_for(env).not_nil!
  config = Patty::Config.instance
  config.server.bind = env.params.body["bind"]?.to_s.strip.presence || "127.0.0.1"
  config.server.port = env.params.body["port"]?.to_s.to_i? || 7629
  config.caddy.binary = env.params.body["caddy_binary"]?.to_s.strip.presence || "caddy"
  config.caddy.validate_before_reload = env.params.body["validate_before_reload"]? == "on"
  config.caddy.reload_after_apply = env.params.body["reload_after_apply"]? == "on"
  config.save
  Patty::Util::ActionLog.log("Settings saved.")
  session.flash!("success", "Settings saved. Server changes apply after restarting Patty.")
  env.redirect "/settings"
end

# --- logs --------------------------------------------------------------------

get "/logs" do |env|
  session = Patty::Auth.session_for(env).not_nil!
  csrf = session.csrf_token
  flash = session.take_flash
  lines = Patty::Util::ActionLog.tail
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
              json.field "service", p.service.label
              json.field "route_enabled", p.route_enabled
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
  {"name", "program", "caddy", "description", "category", "id"}.each do |key|
    values[key] = env.params.body[key]?.to_s.gsub("\r\n", "\n")
  end
  values
end

private def profile_from_form(v : Hash(String, String), id : String?) : Patty::Profile
  Patty::Profile.new(
    1,
    v["name"].strip,
    v["program"].strip,
    v["caddy"],
    id: id,
    description: v["description"]?.try(&.strip.presence),
    category: v["category"]?.try(&.strip.presence),
  )
end

private def profile_status(profile : Patty::Profile) : Patty::Core::State::ProfileStatus
  status, adapter = Patty::Services::Manager.status(profile.program)
  Patty::Core::State::ProfileStatus.new(
    id: profile.slug,
    name: profile.name,
    program: profile.program,
    service: status,
    adapter: adapter,
    route_enabled: Patty::Caddy::Snippets.enabled?(profile.slug),
    open_url: profile.open_url,
    description: profile.description,
  )
end

# Keeps a custom id when free, otherwise picks a collision-free variant.
private def import_id_for(profile : Patty::Profile) : String
  existing = Patty::Profiles::Store.ids
  base = profile.id || Patty::Profiles::IdGenerator.slugify(profile.name)
  Patty::Profiles::IdGenerator.generate(base, existing)
end
