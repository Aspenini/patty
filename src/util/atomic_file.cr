module Patty::Util::AtomicFile
  def self.write(path : String, content : String, permissions : Int32? = nil)
    write_bytes(path, content.to_slice, permissions)
  end

  def self.write(path : String, content : Bytes, permissions : Int32? = nil)
    write_bytes(path, content, permissions)
  end

  private def self.write_bytes(path : String, content : Bytes, permissions : Int32?)
    dir = File.dirname(path)
    Dir.mkdir_p(dir)
    tmp = File.join(dir, ".#{File.basename(path)}.tmp-#{Random::Secure.hex(8)}")

    begin
      File.open(tmp, "wb") do |file|
        file.write(content)
        file.fsync
      end
      File.chmod(tmp, permissions) if permissions
      File.rename(tmp, path)
    ensure
      File.delete(tmp) if File.exists?(tmp)
    end
  end
end
