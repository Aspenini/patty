require "./spec_helper"

describe Patty::Profiles::Warnings do
  it "warns about public file servers without access control" do
    profile = Patty::Profile.new(
      caddy: "files.example.com {\n    root * /srv/files\n    file_server\n}\n",
      id: "files")

    Patty::Profiles::Warnings.for(profile).should_not be_empty
  end

  it "does not warn for localhost or authenticated file servers" do
    local = Patty::Profile.new(
      caddy: "files.localhost {\n    file_server\n}\n",
      id: "local")
    secured = Patty::Profile.new(
      caddy: "files.example.com {\n    basic_auth { alice hash }\n    file_server\n}\n",
      id: "protected")

    Patty::Profiles::Warnings.for(local).should be_empty
    Patty::Profiles::Warnings.for(secured).should be_empty
  end
end
