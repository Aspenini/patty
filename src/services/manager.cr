module Patty::Services
  # Picks the platform-native adapter that can control a given program.
  module Manager
    @@adapters : Array(Adapter)?

    def self.adapters : Array(Adapter)
      @@adapters ||= begin
        list = [] of Adapter
        list << MacBrewAdapter.new if Util::Platform.macos?
        list << LinuxSystemdAdapter.new if Util::Platform.linux?
        list << WindowsServiceAdapter.new if Util::Platform.windows?
        list
      end
    end

    def self.adapters=(adapters : Array(Adapter))
      @@adapters = adapters
    end

    def self.reset_adapters!
      @@adapters = nil
    end

    def self.adapter_for(program : String) : Adapter?
      adapters.find(&.available?(program))
    end

    def self.start(program : String) : Result
      with_adapter(program, &.start(program))
    end

    def self.stop(program : String) : Result
      with_adapter(program, &.stop(program))
    end

    def self.restart(program : String) : Result
      with_adapter(program, &.restart(program))
    end

    # Status plus the human name of the adapter that owns the program.
    def self.status(program : String) : {Status, String?}
      if adapter = adapter_for(program)
        {adapter.status(program), adapter.name}
      else
        {Status::NotFound, nil}
      end
    end

    private def self.with_adapter(program : String, & : Adapter -> Result) : Result
      if adapter = adapter_for(program)
        yield adapter
      else
        Result.failure("No service adapter found for \"#{program}\".",
          adapter_hint(program))
      end
    end

    private def self.adapter_hint(program : String) : String
      if Util::Platform.windows?
        "Use the Windows service name shown in Services, then make sure Patty has permission to control it."
      elsif Util::Platform.linux?
        "Install #{program} as a systemd system service or check the unit name."
      else
        "Install it as a Homebrew service (brew install #{program}) or check the program name."
      end
    end
  end
end
