require "./spec_helper"

PROGRAM_PATTYFILE = <<-YAML
program: jellyfin

caddy: |
  jellyfin.localhost {
      reverse_proxy 127.0.0.1:8096
  }
YAML

CADDY_ONLY_PATTYFILE = <<-YAML
caddy: |
  files.localhost {
      root * /srv/files
      file_server
  }
YAML

describe Patty::Profiles::Parser do
  it "parses a program-backed pattyfile" do
    profile = Patty::Profiles::Parser.parse(PROGRAM_PATTYFILE)
    profile.program.should eq "jellyfin"
    profile.caddy.should contain "reverse_proxy 127.0.0.1:8096"
    profile.id.should be_nil
  end

  it "parses a Caddy-only pattyfile" do
    profile = Patty::Profiles::Parser.parse(CADDY_ONLY_PATTYFILE)
    profile.program.should be_nil
    profile.caddy.should contain "file_server"
  end

  it "raises a friendly error for missing caddy" do
    expect_raises(Patty::Profiles::ParseError, /caddy/) do
      Patty::Profiles::Parser.parse("program: jellyfin\n")
    end
  end

  it "rejects every unsupported top-level field" do
    {"patty", "name", "id", "description", "category"}.each do |field|
      expect_raises(Patty::Profiles::ParseError) do
        Patty::Profiles::Parser.parse("#{field}: value\ncaddy: test.localhost {}\n")
      end
    end
  end

  it "raises ParseError for invalid YAML" do
    expect_raises(Patty::Profiles::ParseError) do
      Patty::Profiles::Parser.parse(": : :")
    end
  end
end

describe Patty::Profiles::Validator do
  it "accepts both supported profile shapes" do
    Patty::Profiles::Validator.validate(
      Patty::Profiles::Parser.parse(PROGRAM_PATTYFILE)).should be_empty
    Patty::Profiles::Validator.validate(
      Patty::Profiles::Parser.parse(CADDY_ONLY_PATTYFILE)).should be_empty
  end

  it "rejects shell commands as program" do
    ["jellyfin && rm -rf /", "a;b", "a|b", "powershell -Command x", "$(boom)"].each do |bad|
      profile = Patty::Profile.new(caddy: "x.localhost {\n}\n", program: bad)
      Patty::Profiles::Validator.validate(profile).should_not be_empty
    end
  end

  it "rejects empty provided programs and Caddy snippets" do
    Patty::Profiles::Validator.validate(
      Patty::Profile.new(caddy: "x.localhost {}", program: "")).join.should contain "program"
    Patty::Profiles::Validator.validate(
      Patty::Profile.new(caddy: " \n")).join.should contain "caddy"
  end

  it "rejects bad filename identities" do
    profile = Patty::Profile.new(caddy: "x {\n}\n", id: "Bad Id!")
    Patty::Profiles::Validator.validate(profile).join.should contain "filename"
  end
end

describe Patty::Profiles::IdGenerator do
  it "slugifies filename stems" do
    Patty::Profiles::IdGenerator.slugify("Jellyfin").should eq "jellyfin"
    Patty::Profiles::IdGenerator.slugify("My Cool App").should eq "my-cool-app"
    Patty::Profiles::IdGenerator.slugify("  Wild!! Name?? ").should eq "wild-name"
    Patty::Profiles::IdGenerator.slugify("???").should eq "profile"
  end

  it "avoids collisions with a numeric suffix" do
    existing = ["jellyfin", "jellyfin-2"]
    Patty::Profiles::IdGenerator.generate("Jellyfin", existing).should eq "jellyfin-3"
  end
end

describe Patty::Profile do
  it "exports a minimal program-backed pattyfile that round-trips" do
    profile = Patty::Profiles::Parser.parse(PROGRAM_PATTYFILE)
    exported = profile.to_pattyfile
    reparsed = Patty::Profiles::Parser.parse(exported)

    reparsed.program.should eq profile.program
    reparsed.caddy.strip.should eq profile.caddy.strip
    exported.should_not contain "name:"
    exported.should_not contain "patty:"
  end

  it "exports a minimal Caddy-only pattyfile that round-trips" do
    profile = Patty::Profiles::Parser.parse(CADDY_ONLY_PATTYFILE)
    exported = profile.to_pattyfile
    reparsed = Patty::Profiles::Parser.parse(exported)

    exported.starts_with?("caddy: |\n").should be_true
    exported.should_not contain "program:"
    reparsed.program.should be_nil
    reparsed.caddy.strip.should eq profile.caddy.strip
  end

  it "infers an open url from the snippet" do
    profile = Patty::Profiles::Parser.parse(PROGRAM_PATTYFILE)
    profile.open_url.should eq "https://jellyfin.localhost"

    port_only = Patty::Profile.new(caddy: ":8080 {\n    respond \"hi\"\n}\n")
    port_only.open_url.should eq "http://localhost:8080"
  end

  it "only exposes http and https open urls" do
    Patty::Profile.new(caddy: "javascript://alert(1) {\n}\n").open_url.should be_nil
    Patty::Profile.new(caddy: "file:///tmp/secret {\n}\n").open_url.should be_nil
    Patty::Profile.new(caddy: "http:// {\n}\n").open_url.should be_nil
    Patty::Profile.new(caddy: "http://localhost:8080 {\n}\n").open_url.should eq "http://localhost:8080"
    Patty::Profile.new(caddy: "https://example.test {\n}\n").open_url.should eq "https://example.test"
  end
end

describe Patty::Profiles::Store do
  it "saves, finds, lists and deletes profiles by filename identity" do
    fresh_home!
    profile = Patty::Profiles::Parser.parse(PROGRAM_PATTYFILE)
    profile.id = "jellyfin"
    saved = Patty::Profiles::Store.save(profile)
    saved.slug.should eq "jellyfin"

    found = Patty::Profiles::Store.find("jellyfin").not_nil!
    found.name.should eq "jellyfin"
    found.program.should eq "jellyfin"

    Patty::Profiles::Store.ids.should eq ["jellyfin"]

    Patty::Profiles::Store.delete("jellyfin")
    Patty::Profiles::Store.find("jellyfin").should be_nil
  end

  it "derives identity from an existing stored filename" do
    fresh_home!
    path = File.join(Patty::Util::Paths.profiles_dir, "static-files.pattyfile")
    File.write(path, CADDY_ONLY_PATTYFILE)

    profile = Patty::Profiles::Store.find("static-files").not_nil!
    profile.slug.should eq "static-files"
    profile.name.should eq "static-files"
  end

  it "requires identity before saving" do
    fresh_home!
    profile = Patty::Profiles::Parser.parse(CADDY_ONLY_PATTYFILE)
    expect_raises(ArgumentError, /identity/) do
      Patty::Profiles::Store.save(profile)
    end
  end
end
