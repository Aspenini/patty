module Patty::Profiles::Validator
  # Plain names only — never a shell command (spec §18/§32).
  PROGRAM_RE = /\A[A-Za-z0-9][A-Za-z0-9._@-]*\z/
  ID_RE      = /\A[a-z0-9][a-z0-9-]*\z/

  def self.validate(profile : Profile) : Array(String)
    errors = [] of String
    errors << "patty version must be 1 (got #{profile.patty})" unless profile.patty == 1
    errors << "name must not be empty" if profile.name.strip.empty?

    program = profile.program.strip
    if program.empty?
      errors << "program must not be empty"
    elsif !PROGRAM_RE.matches?(program)
      errors << "program must be a plain service/executable name " \
                "(letters, numbers, dots, dashes) — not a shell command"
    end

    errors << "caddy snippet must not be empty" if profile.caddy.strip.empty?

    if id = profile.id
      unless ID_RE.matches?(id)
        errors << "id must be a lowercase slug (letters, numbers, dashes)"
      end
    end

    errors
  end
end
