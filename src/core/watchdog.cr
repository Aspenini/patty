module Patty::Core::Watchdog
  INTERVAL = 15.seconds

  def self.start
    spawn do
      loop do
        sleep INTERVAL
        if result = check_once
          Util::ActionLog.log(result.message)
          Util::ActionLog.log(result.detail.not_nil!) if result.detail
        end
      rescue ex
        Util::ActionLog.log("Caddy watchdog error: #{ex.message}")
      end
    end
  end

  def self.check_once : Result?
    return nil if Caddy::Snippets.files.empty?
    return nil if Caddy::Reloader.running?
    Caddy::Manager.reload_active
  end
end
