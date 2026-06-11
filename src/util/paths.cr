# All filesystem locations Patty uses. `PATTY_HOME` overrides the data dir,
# which keeps specs and portable setups away from the real user data.
module Patty::Util::Paths
  def self.data_dir : String
    ENV["PATTY_HOME"]? || File.join(Path.home.to_s, "Library", "Application Support", "Patty")
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
    else
      File.join(Path.home.to_s, "Library", "Logs", "Patty")
    end
  end

  def self.log_file : String
    File.join(log_dir, "patty.log")
  end

  def self.ensure_all!
    [data_dir, profiles_dir, enabled_dir, active_dir, backups_dir, log_dir].each do |dir|
      Dir.mkdir_p(dir)
    end
  end
end
