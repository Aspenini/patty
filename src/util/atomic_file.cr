module Patty::Util::AtomicFile
  def self.write(path : String, content : String, permissions : Int32? = nil)
    dir = File.dirname(path)
    Dir.mkdir_p(dir)
    tmp = File.join(dir, ".#{File.basename(path)}.tmp-#{Random::Secure.hex(8)}")

    begin
      File.open(tmp, "w") do |file|
        file << content
        file.fsync
      end
      File.chmod(tmp, permissions) if permissions
      File.rename(tmp, path)
    ensure
      File.delete(tmp) if File.exists?(tmp)
    end
  end
end
