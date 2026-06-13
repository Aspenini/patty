module Patty::Caddy::DashboardRoute
  extend self

  ID = "__patty-dashboard"

  def dashboard_snippet(config : Config) : String?
    return nil unless Auth.password_set?
    address = DashboardAddress.normalize(config.caddy.dashboard_address)
    return nil unless address

    String.build do |io|
      io << "# Managed by Patty - dashboard route\n"
      io << address << " {\n"
      io << "    reverse_proxy " << proxy_target(config.server) << "\n"
      io << "}\n"
    end
  end

  def sync_file(config : Config) : Bool
    content = dashboard_snippet(config)
    path = Snippets.path_for(ID)
    current = File.read(path) if File.exists?(path)
    return false if current == content

    if content
      Snippets.write(ID, content)
    else
      Snippets.remove(ID)
    end
    true
  end

  private def proxy_target(server : Config::ServerSettings) : String
    host = server.bind
    host = "127.0.0.1" if {"0.0.0.0", "::", "[::]"}.includes?(host)
    host = "[#{host}]" if host.includes?(':') && !host.starts_with?('[')
    "#{host}:#{server.port}"
  end
end
