module Patty::Profiles::IdGenerator
  def self.slugify(filename_stem : String) : String
    slug = filename_stem.downcase.gsub(/[^a-z0-9]+/, "-").strip('-')
    slug.empty? ? "profile" : slug
  end

  def self.generate(filename_stem : String, existing : Array(String) = [] of String) : String
    base = slugify(filename_stem)
    return base unless existing.includes?(base)
    n = 2
    while existing.includes?("#{base}-#{n}")
      n += 1
    end
    "#{base}-#{n}"
  end
end
