# Append-only action log shown on the Logs page. Every user-visible action
# (start/stop, route changes, Caddy validate/reload) lands here.
module Patty::Util::ActionLog
  @@mutex = Mutex.new

  def self.log(message : String)
    line = "[#{Time.local.to_s("%Y-%m-%d %H:%M:%S")}] #{message}"
    @@mutex.synchronize do
      Dir.mkdir_p(Paths.log_dir)
      File.open(Paths.log_file, "a", &.puts(line))
    end
    puts line
  end

  def self.tail(lines : Int32 = 200) : Array(String)
    return [] of String unless File.exists?(Paths.log_file)
    File.read_lines(Paths.log_file).last(lines)
  end
end
