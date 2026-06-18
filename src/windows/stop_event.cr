{% if flag?(:windows) %}
  @[Link("kernel32")]
  lib PattyStopEventKernel32
    alias Handle = Void*

    fun close_handle = CloseHandle(handle : Handle) : Int32
    fun open_event = OpenEventW(desired_access : UInt32, inherit_handle : Int32, name : UInt16*) : Handle
    fun wait_for_single_object = WaitForSingleObject(handle : Handle, milliseconds : UInt32) : UInt32
  end

  module Patty::Windows::StopEvent
    extend self

    SYNCHRONIZE  = 0x00100000_u32
    INFINITE     = UInt32::MAX
    WAIT_OBJECT0 = 0_u32

    @@started = false

    def start
      return if @@started

      name = ENV["PATTY_STOP_EVENT"]?
      return if name.nil? || name.empty?

      @@started = true
      Thread.new(name: "Patty stop event") { wait(name) }
    end

    private def wait(name : String)
      event = PattyStopEventKernel32.open_event(
        SYNCHRONIZE,
        0,
        Crystal::System.to_wstr(name),
      )
      if event.null?
        Util::ActionLog.log("Windows tray stop event could not be opened.")
        return
      end

      result = PattyStopEventKernel32.wait_for_single_object(event, INFINITE)
      if result == WAIT_OBJECT0
        Util::ActionLog.log("Patty stopping from the Windows tray.")
        Kemal.stop if Kemal.config.running
      else
        Util::ActionLog.log("Windows tray stop event ended unexpectedly.")
      end
    rescue ex
      Util::ActionLog.log("Windows tray stop event failed: #{ex.message}")
    ensure
      PattyStopEventKernel32.close_handle(event) if event && !event.null?
    end
  end
{% else %}
  module Patty::Windows::StopEvent
    def self.start
    end
  end
{% end %}
