module Patty::Profiles::IdGenerator
  def self.slugify(name : String) : String
    slug = name.downcase.gsub(/[^a-z0-9]+/, "-").strip('-')
    slug.empty? ? "app" : slug
  end

  def self.generate(name : String, existing : Array(String) = [] of String) : String
    base = slugify(name)
    return base unless existing.includes?(base)
    n = 2
    while existing.includes?("#{base}-#{n}")
      n += 1
    end
    "#{base}-#{n}"
  end
end
