# Append-only action log shown on the Logs page. Every user-visible action
# (start/stop, route changes, Caddy validate/reload) lands here.
module Patty::Util::ActionLog
  MAX_FILE_BYTES = 5 * 1024 * 1024
  MAX_TAIL_BYTES = 1024 * 1024
  ROTATIONS      = 3

  @@mutex = Mutex.new

  def self.log(message : String)
    line = "[#{Time.local.to_s("%Y-%m-%d %H:%M:%S")}] #{message}"
    @@mutex.synchronize do
      Dir.mkdir_p(Paths.log_dir)
      rotate_if_needed(Paths.log_file)
      File.open(Paths.log_file, "a", &.puts(line))
    end
    puts line
  end

  def self.rotate_caddy_before_start!
    @@mutex.synchronize { rotate_if_needed(Paths.caddy_log_file) }
  end

  def self.tail(lines : Int32 = 200) : Array(String)
    tail_file(Paths.log_file, lines)
  end

  def self.tail_file(path : String, lines : Int32 = 200) : Array(String)
    return [] of String unless File.exists?(path)
    File.open(path) do |file|
      size = file.size
      offset = Math.max(0_i64, size - MAX_TAIL_BYTES)
      file.seek(offset)
      content = file.gets_to_end
      values = content.lines(chomp: true)
      values.shift if offset > 0 && !content.starts_with?('\n')
      values.last(lines)
    end
  end

  private def self.rotate_if_needed(path : String)
    return unless File.exists?(path) && File.size(path) >= MAX_FILE_BYTES

    (ROTATIONS - 1).downto(1) do |index|
      move_replacing("#{path}.#{index}", "#{path}.#{index + 1}")
    end
    move_replacing(path, "#{path}.1")
  end

  private def self.move_replacing(source : String, destination : String)
    return unless File.exists?(source)
    File.delete(destination) if File.exists?(destination)
    File.rename(source, destination)
  end
end
