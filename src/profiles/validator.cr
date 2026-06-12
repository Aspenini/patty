module Patty::Profiles::Validator
  # Plain names only - never a shell command.
  PROGRAM_RE = /\A[A-Za-z0-9][A-Za-z0-9._@-]*\z/
  ID_RE      = /\A[a-z0-9][a-z0-9-]*\z/

  def self.validate(profile : Profile) : Array(String)
    errors = [] of String

    if program = profile.program
      if program.strip.empty?
        errors << "program must not be empty when provided"
      elsif !PROGRAM_RE.matches?(program)
        errors << "program must be a plain service/executable name " \
                  "(letters, numbers, dots, dashes) - not a shell command"
      end
    end

    errors << "caddy snippet must not be empty" if profile.caddy.strip.empty?

    if id = profile.id
      unless ID_RE.matches?(id)
        errors << "filename must be a lowercase slug (letters, numbers, dashes)"
      end
    end

    errors
  end
end
