require "./spec_helper"

describe Patty::Util::ActionLog do
  it "reads only the tail of large files" do
    fresh_home!
    path = Patty::Util::Paths.log_file
    File.open(path, "w") do |file|
      250.times { |index| file.puts "line #{index}" }
    end

    tail = Patty::Util::ActionLog.tail(3)

    tail.should eq(["line 247", "line 248", "line 249"])
  end
end
