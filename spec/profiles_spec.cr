require "./spec_helper"

SIMPLE_PATTYFILE = <<-YAML
patty: 1

name: Jellyfin
program: jellyfin

caddy: |
  jellyfin.localhost {
      reverse_proxy 127.0.0.1:8096
  }
YAML

describe Patty::Profiles::Parser do
  it "parses a simple pattyfile" do
    profile = Patty::Profiles::Parser.parse(SIMPLE_PATTYFILE)
    profile.patty.should eq 1
    profile.name.should eq "Jellyfin"
    profile.program.should eq "jellyfin"
    profile.caddy.should contain "reverse_proxy 127.0.0.1:8096"
    profile.slug.should eq "jellyfin"
  end

  it "raises a friendly error for missing fields" do
    expect_raises(Patty::Profiles::ParseError, /program/) do
      Patty::Profiles::Parser.parse("patty: 1\nname: X\ncaddy: y\n")
    end
  end

  it "raises ParseError for invalid YAML" do
    expect_raises(Patty::Profiles::ParseError) do
      Patty::Profiles::Parser.parse(": : :")
    end
  end
end

describe Patty::Profiles::Validator do
  it "accepts a valid profile" do
    profile = Patty::Profiles::Parser.parse(SIMPLE_PATTYFILE)
    Patty::Profiles::Validator.validate(profile).should be_empty
  end

  it "rejects shell commands as program" do
    ["jellyfin && rm -rf /", "a;b", "a|b", "powershell -Command x", "$(boom)"].each do |bad|
      profile = Patty::Profile.new(1, "X", bad, "x.localhost {\n}\n")
      Patty::Profiles::Validator.validate(profile).should_not be_empty
    end
  end

  it "rejects wrong patty version" do
    profile = Patty::Profile.new(2, "X", "x", "x.localhost {\n}\n")
    Patty::Profiles::Validator.validate(profile).join.should contain "version"
  end

  it "rejects bad custom ids" do
    profile = Patty::Profile.new(1, "X", "x", "x {\n}\n", id: "Bad Id!")
    Patty::Profiles::Validator.validate(profile).join.should contain "id"
  end
end

describe Patty::Profiles::IdGenerator do
  it "slugifies names" do
    Patty::Profiles::IdGenerator.slugify("Jellyfin").should eq "jellyfin"
    Patty::Profiles::IdGenerator.slugify("My Cool App").should eq "my-cool-app"
    Patty::Profiles::IdGenerator.slugify("  Wild!! Name?? ").should eq "wild-name"
    Patty::Profiles::IdGenerator.slugify("???").should eq "app"
  end

  it "avoids collisions with a numeric suffix" do
    existing = ["jellyfin", "jellyfin-2"]
    Patty::Profiles::IdGenerator.generate("Jellyfin", existing).should eq "jellyfin-3"
  end
end

describe Patty::Profile do
  it "exports a canonical pattyfile that round-trips" do
    profile = Patty::Profiles::Parser.parse(SIMPLE_PATTYFILE)
    exported = profile.to_pattyfile
    reparsed = Patty::Profiles::Parser.parse(exported)
    reparsed.name.should eq profile.name
    reparsed.program.should eq profile.program
    reparsed.caddy.strip.should eq profile.caddy.strip
  end

  it "quotes odd names in export" do
    profile = Patty::Profile.new(1, "App: with colons", "app", "a.localhost {\n}\n")
    reparsed = Patty::Profiles::Parser.parse(profile.to_pattyfile)
    reparsed.name.should eq "App: with colons"
  end

  it "infers an open url from the snippet" do
    profile = Patty::Profiles::Parser.parse(SIMPLE_PATTYFILE)
    profile.open_url.should eq "https://jellyfin.localhost"

    port_only = Patty::Profile.new(1, "X", "x", ":8080 {\n    respond \"hi\"\n}\n")
    port_only.open_url.should eq "http://localhost:8080"
  end
end

describe Patty::Profiles::Store do
  it "saves, finds, lists and deletes profiles" do
    fresh_home!
    profile = Patty::Profiles::Parser.parse(SIMPLE_PATTYFILE)
    saved = Patty::Profiles::Store.save(profile)
    saved.slug.should eq "jellyfin"

    found = Patty::Profiles::Store.find("jellyfin").not_nil!
    found.name.should eq "Jellyfin"

    Patty::Profiles::Store.ids.should eq ["jellyfin"]

    Patty::Profiles::Store.delete("jellyfin")
    Patty::Profiles::Store.find("jellyfin").should be_nil
  end

  it "assigns a collision-free id on save" do
    fresh_home!
    a = Patty::Profile.new(1, "Same Name", "prog-a", "a.localhost {\n}\n")
    b = Patty::Profile.new(1, "Same Name", "prog-b", "b.localhost {\n}\n")
    Patty::Profiles::Store.save(a).slug.should eq "same-name"
    Patty::Profiles::Store.save(b).slug.should eq "same-name-2"
  end
end
