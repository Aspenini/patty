# All filesystem locations Patty uses. `PATTY_HOME` overrides the data dir,
# which keeps specs and portable setups away from the real user data.
module Patty::Util::Paths
  def self.data_dir : String
    ENV["PATTY_HOME"]? || platform_data_dir
  end

  def self.profiles_dir : String
    File.join(data_dir, "profiles")
  end

  def self.enabled_dir : String
    File.join(data_dir, "enabled")
  end

  def self.active_dir : String
    File.join(data_dir, "active")
  end

  def self.backups_dir : String
    File.join(data_dir, "backups")
  end

  def self.active_caddyfile : String
    File.join(active_dir, "Caddyfile")
  end

  def self.config_file : String
    File.join(data_dir, "patty.yml")
  end

  def self.auth_file : String
    File.join(data_dir, "auth.yml")
  end

  def self.log_dir : String
    if ENV["PATTY_HOME"]?
      File.join(data_dir, "logs")
    elsif Util::Platform.windows?
      if base = ENV["LOCALAPPDATA"]?
        File.join(base, "Patty", "Logs")
      else
        File.join(data_dir, "logs")
      end
    elsif Util::Platform.linux?
      File.join(ENV["XDG_STATE_HOME"]? || File.join(Path.home.to_s, ".local", "state"), "patty")
    else
      File.join(Path.home.to_s, "Library", "Logs", "Patty")
    end
  end

  def self.log_file : String
    File.join(log_dir, "patty.log")
  end

  def self.caddy_log_file : String
    File.join(log_dir, "caddy.log")
  end

  def self.ensure_all!
    migrate_legacy_windows_data!
    [data_dir, profiles_dir, enabled_dir, active_dir, backups_dir, log_dir].each do |dir|
      Dir.mkdir_p(dir)
    end
  end

  private def self.platform_data_dir : String
    if Util::Platform.windows?
      File.join(ENV["APPDATA"]? || File.join(Path.home.to_s, "AppData", "Roaming"), "Patty")
    elsif Util::Platform.linux?
      File.join(ENV["XDG_DATA_HOME"]? || File.join(Path.home.to_s, ".local", "share"), "patty")
    else
      File.join(Path.home.to_s, "Library", "Application Support", "Patty")
    end
  end

  private def self.migrate_legacy_windows_data!
    return unless Util::Platform.windows?
    return if ENV["PATTY_HOME"]?

    legacy = File.join(Path.home.to_s, "Library", "Application Support", "Patty")
    target = platform_data_dir
    marker = File.join(target, ".legacy-data-migrated")
    return if File.exists?(marker) || !Dir.exists?(legacy)

    merge_missing(legacy, target)
    File.write(marker, "Migrated from #{legacy}\n")
  rescue ex
    STDERR.puts "Could not migrate Patty data to #{target}: #{ex.message}"
  end

  private def self.merge_missing(source : String, target : String)
    Dir.mkdir_p(target)
    Dir.children(source).each do |name|
      source_path = File.join(source, name)
      target_path = File.join(target, name)
      if Dir.exists?(source_path)
        merge_missing(source_path, target_path)
      elsif !File.exists?(target_path)
        File.copy(source_path, target_path)
      end
    end
  end
end
