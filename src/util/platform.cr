module Patty::Util::Platform
  def self.macos? : Bool
    {% if flag?(:darwin) %} true {% else %} false {% end %}
  end

  def self.linux? : Bool
    {% if flag?(:linux) %} true {% else %} false {% end %}
  end

  def self.windows? : Bool
    {% if flag?(:windows) %} true {% else %} false {% end %}
  end

  def self.name : String
    if macos?
      "macOS"
    elsif linux?
      "Linux"
    elsif windows?
      "Windows"
    else
      "unknown"
    end
  end
end
