require "./spec_helper"

describe Patty::Util::ProcessRunner do
  it "captures command output" do
    result =
      {% if flag?(:windows) %}
        Patty::Util::ProcessRunner.run("cmd.exe", ["/d", "/c", "echo hidden"])
      {% else %}
        Patty::Util::ProcessRunner.run("printf", ["hidden"])
      {% end %}

    result.success?.should be_true
    result.stdout.should contain "hidden"
    result.stderr.should be_empty
  end

  it "starts a background command with file logging" do
    log = File.join(Patty::Util::Paths.log_dir, "process-runner-spec.log")
    result =
      {% if flag?(:windows) %}
        Patty::Util::ProcessRunner.start_logged(
          "cmd.exe", ["/d", "/c", "echo background"], log)
      {% else %}
        Patty::Util::ProcessRunner.start_logged(
          "sh", ["-c", "printf background"], log)
      {% end %}

    result.success?.should be_true
    20.times do
      break if File.exists?(log) && File.read(log).includes?("background")
      sleep 25.milliseconds
    end
    File.read(log).should contain "background"
  end
end
