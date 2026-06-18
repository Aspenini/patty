{% if flag?(:windows) %}
  require "yaml"
  require "../util/platform"
  require "../util/paths"

  @[Link("user32")]
  lib PattyTrayUser32
    alias Handle = Void*
    alias WndProc = (Handle, UInt32, UInt64, Int64) -> Int64

    struct Point
      x : Int32
      y : Int32
    end

    struct Message
      hwnd : Handle
      message : UInt32
      w_param : UInt64
      l_param : Int64
      time : UInt32
      point : Point
      private_data : UInt32
    end

    struct WindowClass
      style : UInt32
      wnd_proc : WndProc
      class_extra : Int32
      window_extra : Int32
      instance : Handle
      icon : Handle
      cursor : Handle
      background : Handle
      menu_name : UInt16*
      class_name : UInt16*
    end

    fun append_menu = AppendMenuW(menu : Handle, flags : UInt32, item : UInt64, text : UInt16*) : Int32
    fun create_popup_menu = CreatePopupMenu : Handle
    fun create_window = CreateWindowExW(
      extended_style : UInt32,
      class_name : UInt16*,
      window_name : UInt16*,
      style : UInt32,
      x : Int32,
      y : Int32,
      width : Int32,
      height : Int32,
      parent : Handle,
      menu : Handle,
      instance : Handle,
      param : Void*,
    ) : Handle
    fun default_window_proc = DefWindowProcW(hwnd : Handle, message : UInt32, w_param : UInt64, l_param : Int64) : Int64
    fun destroy_menu = DestroyMenu(menu : Handle) : Int32
    fun destroy_window = DestroyWindow(hwnd : Handle) : Int32
    fun dispatch_message = DispatchMessageW(message : Message*) : Int64
    fun find_window = FindWindowW(class_name : UInt16*, window_name : UInt16*) : Handle
    fun get_cursor_position = GetCursorPos(point : Point*) : Int32
    fun get_message = GetMessageW(message : Message*, hwnd : Handle, minimum : UInt32, maximum : UInt32) : Int32
    fun load_icon = LoadIconW(instance : Handle, name : UInt16*) : Handle
    fun message_box = MessageBoxW(hwnd : Handle, text : UInt16*, caption : UInt16*, kind : UInt32) : Int32
    fun post_message = PostMessageW(hwnd : Handle, message : UInt32, w_param : UInt64, l_param : Int64) : Int32
    fun post_quit_message = PostQuitMessage(code : Int32)
    fun register_class = RegisterClassW(window_class : WindowClass*) : UInt16
    fun register_window_message = RegisterWindowMessageW(name : UInt16*) : UInt32
    fun set_foreground_window = SetForegroundWindow(hwnd : Handle) : Int32
    fun track_popup_menu = TrackPopupMenu(
      menu : Handle,
      flags : UInt32,
      x : Int32,
      y : Int32,
      reserved : Int32,
      hwnd : Handle,
      rectangle : Void*,
    ) : UInt32
    fun translate_message = TranslateMessage(message : Message*) : Int32
  end

  @[Link("shell32")]
  lib PattyTrayShell32
    alias Handle = Void*

    struct Guid
      data1 : UInt32
      data2 : UInt16
      data3 : UInt16
      data4 : StaticArray(UInt8, 8)
    end

    struct NotifyIconData
      size : UInt32
      hwnd : Handle
      id : UInt32
      flags : UInt32
      callback_message : UInt32
      icon : Handle
      tip : StaticArray(UInt16, 128)
      state : UInt32
      state_mask : UInt32
      info : StaticArray(UInt16, 256)
      version : UInt32
      info_title : StaticArray(UInt16, 64)
      info_flags : UInt32
      guid : Guid
      balloon_icon : Handle
    end

    fun notify_icon = Shell_NotifyIconW(message : UInt32, data : NotifyIconData*) : Int32
    fun shell_execute = ShellExecuteW(
      hwnd : Handle,
      operation : UInt16*,
      file : UInt16*,
      parameters : UInt16*,
      directory : UInt16*,
      show : Int32,
    ) : Handle
  end

  @[Link("kernel32")]
  lib PattyTrayKernel32
    alias Handle = Void*

    fun close_handle = CloseHandle(handle : Handle) : Int32
    fun create_event = CreateEventW(attributes : Void*, manual_reset : Int32, initial_state : Int32, name : UInt16*) : Handle
    fun get_module_handle = GetModuleHandleW(name : UInt16*) : Handle
    fun set_event = SetEvent(handle : Handle) : Int32
    fun terminate_process = TerminateProcess(process : Handle, exit_code : UInt32) : Int32
    fun wait_for_single_object = WaitForSingleObject(handle : Handle, milliseconds : UInt32) : UInt32
  end

  module Patty::Windows::TrayLauncher
    extend self

    CLASS_NAME   = "PattyTrayWindow"
    WINDOW_TITLE = "Patty"
    ICON_ID      = 1_u32

    WM_CLOSE         = 0x0010_u32
    WM_COMMAND       = 0x0111_u32
    WM_DESTROY       = 0x0002_u32
    WM_LBUTTONDBLCLK = 0x0203_u32
    WM_RBUTTONUP     = 0x0205_u32
    WM_CONTEXTMENU   = 0x007B_u32
    WM_TRAY_CALLBACK = 0x8001_u32

    NIM_ADD    = 0_u32
    NIM_DELETE = 2_u32

    NIF_MESSAGE = 0x0001_u32
    NIF_ICON    = 0x0002_u32
    NIF_TIP     = 0x0004_u32

    MF_STRING    = 0x0000_u32
    MF_SEPARATOR = 0x0800_u32

    TPM_RIGHTBUTTON = 0x0002_u32
    TPM_NONOTIFY    = 0x0080_u32
    TPM_RETURNCMD   = 0x0100_u32

    MENU_OPEN = 1001_u64
    MENU_LOGS = 1002_u64
    MENU_EXIT = 1003_u64

    IDI_APPLICATION = 32512_u64
    SW_SHOWNORMAL   =         1

    MB_OK        = 0x00000000_u32
    MB_ICONERROR = 0x00000010_u32

    DETACHED_PROCESS = 0x00000008_u32
    INFINITE         = UInt32::MAX
    WAIT_OBJECT0     =          0_u32
    WAIT_TIMEOUT     = 0x00000102_u32

    STOP_EVENT_PREFIX = "Local\\PattyStop-"

    @@window = Pointer(Void).null
    @@process_handle = Pointer(Void).null
    @@process_thread = Pointer(Void).null
    @@stop_event = Pointer(Void).null
    @@taskbar_created = 0_u32
    @@stopping = false
    @@shutdown_requested = false

    def run
      prepare_logging
      Util::Paths.ensure_all!
      return if open_existing
      return unless create_hidden_window

      add_icon
      unless launch_server
        show_error("Patty could not start. Check the Patty log for details.")
        return
      end

      message_loop
    rescue ex
      log("Windows tray failed: #{ex.message}")
      show_error("Patty tray failed. Check the Patty log for details.")
    ensure
      shutdown_server
      delete_icon
      close_handles
      @@window = Pointer(Void).null
    end

    private def prepare_logging
      Dir.mkdir_p(Util::Paths.log_dir)
      File.open(Util::Paths.log_file, "a") do |log|
        STDOUT.reopen(log)
        STDERR.reopen(log)
      end
    end

    private def log(message : String)
      puts "[#{Time.local.to_s("%Y-%m-%d %H:%M:%S")}] #{message}"
    rescue
    end

    private def open_existing : Bool
      window = PattyTrayUser32.find_window(
        Crystal::System.to_wstr(CLASS_NAME),
        Crystal::System.to_wstr(WINDOW_TITLE),
      )
      return false if window.null?

      PattyTrayUser32.post_message(window, WM_TRAY_CALLBACK, ICON_ID, WM_LBUTTONDBLCLK)
      true
    end

    private def create_hidden_window : Bool
      instance = PattyTrayKernel32.get_module_handle(Pointer(UInt16).null)
      class_name = Crystal::System.to_wstr(CLASS_NAME)
      window_title = Crystal::System.to_wstr(WINDOW_TITLE)
      window_class = PattyTrayUser32::WindowClass.new(
        style: 0,
        wnd_proc: ->window_proc(PattyTrayUser32::Handle, UInt32, UInt64, Int64),
        class_extra: 0,
        window_extra: 0,
        instance: instance,
        icon: app_icon(instance),
        cursor: Pointer(Void).null,
        background: Pointer(Void).null,
        menu_name: Pointer(UInt16).null,
        class_name: class_name,
      )

      unless PattyTrayUser32.register_class(pointerof(window_class)) != 0
        log("Windows tray could not register its hidden window.")
        return false
      end

      @@window = PattyTrayUser32.create_window(
        0,
        class_name,
        window_title,
        0,
        0, 0, 0, 0,
        Pointer(Void).null,
        Pointer(Void).null,
        instance,
        Pointer(Void).null,
      )
      if @@window.null?
        log("Windows tray could not create its hidden window.")
        return false
      end

      @@taskbar_created = PattyTrayUser32.register_window_message(Crystal::System.to_wstr("TaskbarCreated"))
      true
    end

    private def message_loop
      message = PattyTrayUser32::Message.new
      while PattyTrayUser32.get_message(pointerof(message), Pointer(Void).null, 0, 0) > 0
        PattyTrayUser32.translate_message(pointerof(message))
        PattyTrayUser32.dispatch_message(pointerof(message))
      end
    end

    private def window_proc(hwnd : PattyTrayUser32::Handle, message : UInt32, w_param : UInt64, l_param : Int64) : Int64
      if message == @@taskbar_created && message != 0
        add_icon
        return 0_i64
      end

      case message
      when WM_TRAY_CALLBACK
        event = l_param.to_u32
        if event == WM_RBUTTONUP || event == WM_CONTEXTMENU
          show_menu(hwnd)
        elsif event == WM_LBUTTONDBLCLK
          open_patty
        end
        0_i64
      when WM_CLOSE
        @@stopping = true
        shutdown_server
        delete_icon
        PattyTrayUser32.destroy_window(hwnd)
        0_i64
      when WM_COMMAND
        handle_command((w_param & 0xffff).to_u32)
        0_i64
      when WM_DESTROY
        PattyTrayUser32.post_quit_message(0)
        0_i64
      else
        PattyTrayUser32.default_window_proc(hwnd, message, w_param, l_param)
      end
    rescue ex
      log("Windows tray message failed: #{ex.message}")
      PattyTrayUser32.default_window_proc(hwnd, message, w_param, l_param)
    end

    private def show_menu(hwnd : PattyTrayUser32::Handle)
      menu = PattyTrayUser32.create_popup_menu
      return if menu.null?

      append(menu, MF_STRING, MENU_OPEN, "Open Patty")
      append(menu, MF_STRING, MENU_LOGS, "Show Logs")
      PattyTrayUser32.append_menu(menu, MF_SEPARATOR, 0, Pointer(UInt16).null)
      append(menu, MF_STRING, MENU_EXIT, "Exit")

      point = PattyTrayUser32::Point.new
      PattyTrayUser32.get_cursor_position(pointerof(point))
      PattyTrayUser32.set_foreground_window(hwnd)
      command = PattyTrayUser32.track_popup_menu(
        menu,
        TPM_RIGHTBUTTON | TPM_NONOTIFY | TPM_RETURNCMD,
        point.x,
        point.y,
        0,
        hwnd,
        Pointer(Void).null,
      )
      PattyTrayUser32.destroy_menu(menu)
      handle_command(command)
    end

    private def append(menu, flags, id, text)
      PattyTrayUser32.append_menu(menu, flags, id, Crystal::System.to_wstr(text))
    end

    private def handle_command(command : UInt32)
      case command.to_u64
      when MENU_OPEN
        open_patty
      when MENU_LOGS
        shell_open(Util::Paths.log_dir)
      when MENU_EXIT
        @@stopping = true
        window = @@window
        PattyTrayUser32.post_message(window, WM_CLOSE, 0, 0) unless window.null?
      end
    end

    private def launch_server : Bool
      executable = server_executable
      unless File.exists?(executable)
        log("Patty CLI executable was not found next to the tray wrapper: #{executable}")
        return false
      end

      event_name = "#{STOP_EVENT_PREFIX}#{Process.pid}"
      @@stop_event = PattyTrayKernel32.create_event(
        Pointer(Void).null,
        1,
        0,
        Crystal::System.to_wstr(event_name),
      )
      if @@stop_event.null?
        log("Windows tray could not create the Patty stop event.")
        return false
      end

      ENV["PATTY_STOP_EVENT"] = event_name
      File.open(Util::Paths.log_file, "a") do |log_file|
        process_info = start_hidden(executable, ["run"], log_file, log_file)
        @@process_handle = process_info.hProcess
        @@process_thread = process_info.hThread
      end
      ENV.delete("PATTY_STOP_EVENT")

      log("Patty tray launched #{executable} run.")
      start_monitor
      true
    rescue ex
      ENV.delete("PATTY_STOP_EVENT")
      log("Windows tray could not launch Patty: #{ex.message}")
      false
    end

    private def start_hidden(command : String, args : Array(String),
                             output : File, error : File) : LibC::PROCESS_INFORMATION
      input = File.open("NUL", "r")
      inherited = [] of LibC::HANDLE
      process_info = LibC::PROCESS_INFORMATION.new
      begin
        startup_info = LibC::STARTUPINFOW.new
        startup_info.cb = sizeof(LibC::STARTUPINFOW)
        startup_info.dwFlags = LibC::STARTF_USESTDHANDLES
        startup_info.hStdInput = duplicate_inheritable(input, inherited)
        startup_info.hStdOutput = duplicate_inheritable(output, inherited)
        startup_info.hStdError = duplicate_inheritable(error, inherited)

        command_line = Process.quote_windows([command] + args)
        created = LibC.CreateProcessW(
          Crystal::System.to_wstr(command),
          Crystal::System.to_wstr(command_line),
          Pointer(LibC::SECURITY_ATTRIBUTES).null,
          Pointer(LibC::SECURITY_ATTRIBUTES).null,
          1,
          DETACHED_PROCESS,
          Pointer(Void).null,
          Crystal::System.to_wstr(File.dirname(command)),
          pointerof(startup_info),
          pointerof(process_info),
        )
        raise IO::Error.from_winerror("Error executing process") if created == 0

        process_info
      ensure
        input.close
        inherited.each { |handle| PattyTrayKernel32.close_handle(handle) }
      end
    end

    private def duplicate_inheritable(file : File, handles : Array(LibC::HANDLE)) : LibC::HANDLE
      duplicate = duplicate_handle(LibC::HANDLE.new(file.fd), true)
      handles << duplicate
      duplicate
    end

    private def duplicate_handle(handle : LibC::HANDLE, inheritable : Bool) : LibC::HANDLE
      process = LibC.GetCurrentProcess
      unless LibC.DuplicateHandle(
               process,
               handle,
               process,
               out duplicate,
               0,
               inheritable ? 1 : 0,
               LibC::DUPLICATE_SAME_ACCESS,
             ) != 0
        raise IO::Error.from_winerror("Could not duplicate process handle")
      end
      duplicate
    end

    private def start_monitor
      handle = @@process_handle
      return if handle.null?

      monitor_handle = duplicate_handle(handle, false)
      Thread.new(name: "Patty server monitor") do
        PattyTrayKernel32.wait_for_single_object(monitor_handle, INFINITE)
        PattyTrayKernel32.close_handle(monitor_handle)
        unless @@stopping
          log("Patty server exited; closing Windows tray.")
          @@stopping = true
          window = @@window
          PattyTrayUser32.post_message(window, WM_CLOSE, 0, 0) unless window.null?
        end
      end
    rescue ex
      log("Windows tray could not start the server monitor: #{ex.message}")
    end

    private def shutdown_server
      return if @@shutdown_requested

      @@shutdown_requested = true
      handle = @@process_handle
      return if handle.null?

      if process_running?(handle)
        event = @@stop_event
        PattyTrayKernel32.set_event(event) unless event.null?
        result = PattyTrayKernel32.wait_for_single_object(handle, 5_000)
        if result == WAIT_TIMEOUT
          log("Patty server did not stop in time; terminating it.")
          PattyTrayKernel32.terminate_process(handle, 1)
          PattyTrayKernel32.wait_for_single_object(handle, 2_000)
        end
      end
    end

    private def process_running?(handle : LibC::HANDLE) : Bool
      PattyTrayKernel32.wait_for_single_object(handle, 0) == WAIT_TIMEOUT
    end

    private def close_handles
      close_handle(pointerof(@@process_thread))
      close_handle(pointerof(@@process_handle))
      close_handle(pointerof(@@stop_event))
    end

    private def close_handle(handle_ref : Pointer(LibC::HANDLE))
      handle = handle_ref.value
      return if handle.null?

      PattyTrayKernel32.close_handle(handle)
      handle_ref.value = Pointer(Void).null
    end

    private def open_patty
      shell_open(server_url)
    end

    private def server_url : String
      bind = "127.0.0.1"
      port = 7629

      path = Util::Paths.config_file
      if File.exists?(path)
        yaml = YAML.parse(File.read(path))
        if server = yaml["server"]?
          bind = server["bind"]?.try(&.as_s?) || bind
          if value = server["port"]?
            port = value.as_i? || value.as_s?.try(&.to_i?) || port
          end
        end
      end

      host = bind
      host = "127.0.0.1" if {"0.0.0.0", "::", "[::]"}.includes?(host)
      host = "[#{host}]" if host.includes?(':') && !host.starts_with?('[')
      "http://#{host}:#{port}"
    rescue ex
      log("Windows tray could not read Patty config: #{ex.message}")
      "http://127.0.0.1:7629"
    end

    private def server_executable : String
      if current = Process.executable_path
        candidate = File.join(File.dirname(current), "patty.exe")
        return candidate if File.exists?(candidate)
      end

      candidate = File.join(Dir.current, "patty.exe")
      return candidate if File.exists?(candidate)

      Process.find_executable("patty.exe") || candidate
    end

    private def shell_open(target : String)
      result = PattyTrayShell32.shell_execute(
        @@window,
        Crystal::System.to_wstr("open"),
        Crystal::System.to_wstr(target),
        Pointer(UInt16).null,
        Pointer(UInt16).null,
        SW_SHOWNORMAL,
      )
      if result.address <= 32
        log("Windows could not open #{target}.")
      end
    end

    private def show_error(message : String)
      PattyTrayUser32.message_box(
        @@window,
        Crystal::System.to_wstr(message),
        Crystal::System.to_wstr("Patty"),
        MB_OK | MB_ICONERROR,
      )
    end

    private def add_icon
      window = @@window
      return if window.null?

      data = notify_icon_data(window)
      unless PattyTrayShell32.notify_icon(NIM_ADD, pointerof(data)) != 0
        log("Windows could not add Patty to the notification area.")
      end
    end

    private def delete_icon
      window = @@window
      return if window.null?

      data = notify_icon_data(window)
      PattyTrayShell32.notify_icon(NIM_DELETE, pointerof(data))
    end

    private def notify_icon_data(window : PattyTrayUser32::Handle) : PattyTrayShell32::NotifyIconData
      instance = PattyTrayKernel32.get_module_handle(Pointer(UInt16).null)
      PattyTrayShell32::NotifyIconData.new(
        size: sizeof(PattyTrayShell32::NotifyIconData).to_u32,
        hwnd: window,
        id: ICON_ID,
        flags: NIF_MESSAGE | NIF_ICON | NIF_TIP,
        callback_message: WM_TRAY_CALLBACK,
        icon: app_icon(instance),
        tip: wide_array("Patty"),
        state: 0,
        state_mask: 0,
        info: StaticArray(UInt16, 256).new(0_u16),
        version: 0,
        info_title: StaticArray(UInt16, 64).new(0_u16),
        info_flags: 0,
        guid: PattyTrayShell32::Guid.new(
          data1: 0,
          data2: 0,
          data3: 0,
          data4: StaticArray(UInt8, 8).new(0_u8),
        ),
        balloon_icon: Pointer(Void).null,
      )
    end

    private def app_icon(instance : PattyTrayUser32::Handle) : PattyTrayUser32::Handle
      icon = PattyTrayUser32.load_icon(instance, Pointer(UInt16).new(ICON_ID.to_u64))
      return icon unless icon.null?
      PattyTrayUser32.load_icon(Pointer(Void).null, Pointer(UInt16).new(IDI_APPLICATION))
    end

    private def wide_array(text : String) : StaticArray(UInt16, 128)
      values = StaticArray(UInt16, 128).new(0_u16)
      text.to_utf16.each_with_index do |value, index|
        break if index >= 127
        values[index] = value
      end
      values
    end
  end
{% else %}
  module Patty::Windows::TrayLauncher
    def self.run
      STDERR.puts "The Patty tray launcher is only available on Windows."
      exit 1
    end
  end
{% end %}
