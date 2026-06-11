module Patty::Profiles
  class ParseError < Exception
  end

  module Parser
    def self.parse(content : String) : Profile
      Profile.from_yaml(content)
    rescue ex : YAML::ParseException
      raise ParseError.new(friendly_message(ex))
    end

    private def self.friendly_message(ex : YAML::ParseException) : String
      message = ex.message || "invalid YAML"
      if match = message.match(/Missing yaml attribute: (\w+)/i)
        "Missing required field: #{match[1]}"
      else
        message
      end
    end
  end
end
