module Patty::Services
  enum Status
    Running
    Stopped
    Unknown
    NotFound

    def label : String
      case self
      in .running?   then "running"
      in .stopped?   then "stopped"
      in .unknown?   then "unknown"
      in .not_found? then "not found"
      end
    end
  end

  # Platform adapter interface (spec §12). Adapters are dumb: they answer
  # "can you control this program?" and do start/stop/restart/status.
  abstract class Adapter
    abstract def name : String
    abstract def available?(program : String) : Bool
    abstract def start(program : String) : Result
    abstract def stop(program : String) : Result
    abstract def restart(program : String) : Result
    abstract def status(program : String) : Status
  end
end
