module Patty
  # Outcome of any core action. `message` is short and user-facing,
  # `detail` carries command output or validation errors when present.
  record Result, ok : Bool, message : String, detail : String? = nil do
    def self.success(message : String, detail : String? = nil) : Result
      new(true, message, detail)
    end

    def self.failure(message : String, detail : String? = nil) : Result
      new(false, message, detail)
    end

    def ok? : Bool
      ok
    end

    def kind : String
      ok ? "success" : "error"
    end
  end
end
