{% if flag?(:windows) %}
  @[Link("user32")]
  lib PattyUser32
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
    fun get_cursor_position = GetCursorPos(point : Point*) : Int32
    fun find_window = FindWindowW(class_name : UInt16*, window_name : UInt16*) : Handle
    fun get_message = GetMessageW(message : Message*, hwnd : Handle, minimum : UInt32, maximum : UInt32) : Int32
    fun load_icon = LoadIconW(instance : Handle, name : UInt16*) : Handle
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
    fun dispatch_message = DispatchMessageW(message : Message*) : Int64
  end

  @[Link("shell32")]
  lib PattyShell32
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
  lib PattyKernel32
    alias Handle = Void*
    fun module_handle = GetModuleHandleW(name : UInt16*) : Handle
  end

  module Patty::Windows::Tray
    extend self

    CLASS_NAME = "PattyTrayWindow"
    ICON_ID    = 1_u32

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

    @@window = Pointer(Void).null
    @@thread : Thread?
    @@taskbar_created = 0_u32
    @@stopping = false

    def start
      return if @@thread
      @@stopping = false
      @@thread = Thread.new(name: "Patty tray") { run }
    end

    def stop
      @@stopping = true
      window = @@window
      PattyUser32.post_message(window, WM_CLOSE, 0, 0) unless window.null?
    end

    def open_existing : Bool
      window = PattyUser32.find_window(
        Crystal::System.to_wstr(CLASS_NAME),
        Crystal::System.to_wstr("Patty"),
      )
      return false if window.null?

      PattyUser32.post_message(window, WM_TRAY_CALLBACK, ICON_ID, WM_LBUTTONDBLCLK)
      true
    end

    private def run
      instance = PattyKernel32.module_handle(Pointer(UInt16).null)
      class_name = Crystal::System.to_wstr(CLASS_NAME)
      title = Crystal::System.to_wstr("Patty")
      window_class = PattyUser32::WindowClass.new(
        style: 0,
        wnd_proc: ->window_proc(PattyUser32::Handle, UInt32, UInt64, Int64),
        class_extra: 0,
        window_extra: 0,
        instance: instance,
        icon: app_icon(instance),
        cursor: Pointer(Void).null,
        background: Pointer(Void).null,
        menu_name: Pointer(UInt16).null,
        class_name: class_name,
      )

      unless PattyUser32.register_class(pointerof(window_class)) != 0
        Util::ActionLog.log("Windows tray could not register its hidden window.")
        return
      end

      @@window = PattyUser32.create_window(
        0,
        class_name,
        title,
        0,
        0, 0, 0, 0,
        Pointer(Void).null,
        Pointer(Void).null,
        instance,
        Pointer(Void).null,
      )
      if @@window.null?
        Util::ActionLog.log("Windows tray could not create its hidden window.")
        return
      end

      @@taskbar_created = PattyUser32.register_window_message(Crystal::System.to_wstr("TaskbarCreated"))
      add_icon

      message = PattyUser32::Message.new
      while PattyUser32.get_message(pointerof(message), Pointer(Void).null, 0, 0) > 0
        PattyUser32.translate_message(pointerof(message))
        PattyUser32.dispatch_message(pointerof(message))
      end
    rescue ex
      Util::ActionLog.log("Windows tray failed: #{ex.message}")
    ensure
      delete_icon
      @@window = Pointer(Void).null
      @@thread = nil
    end

    private def window_proc(hwnd : PattyUser32::Handle, message : UInt32, w_param : UInt64, l_param : Int64) : Int64
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
        unless @@stopping
          @@stopping = true
          Kemal.stop if Kemal.config.running
        end
        delete_icon
        PattyUser32.destroy_window(hwnd)
        0_i64
      when WM_COMMAND
        handle_command((w_param & 0xffff).to_u32)
        0_i64
      when WM_DESTROY
        PattyUser32.post_quit_message(0)
        0_i64
      else
        PattyUser32.default_window_proc(hwnd, message, w_param, l_param)
      end
    rescue ex
      Util::ActionLog.log("Windows tray message failed: #{ex.message}")
      PattyUser32.default_window_proc(hwnd, message, w_param, l_param)
    end

    private def show_menu(hwnd : PattyUser32::Handle)
      menu = PattyUser32.create_popup_menu
      return if menu.null?

      append(menu, MF_STRING, MENU_OPEN, "Open Patty")
      append(menu, MF_STRING, MENU_LOGS, "Show Logs")
      PattyUser32.append_menu(menu, MF_SEPARATOR, 0, Pointer(UInt16).null)
      append(menu, MF_STRING, MENU_EXIT, "Exit")

      point = PattyUser32::Point.new
      PattyUser32.get_cursor_position(pointerof(point))
      PattyUser32.set_foreground_window(hwnd)
      command = PattyUser32.track_popup_menu(
        menu,
        TPM_RIGHTBUTTON | TPM_NONOTIFY | TPM_RETURNCMD,
        point.x,
        point.y,
        0,
        hwnd,
        Pointer(Void).null,
      )
      PattyUser32.destroy_menu(menu)
      handle_command(command)
    end

    private def append(menu, flags, id, text)
      PattyUser32.append_menu(menu, flags, id, Crystal::System.to_wstr(text))
    end

    private def handle_command(command : UInt32)
      case command.to_u64
      when MENU_OPEN
        open_patty
      when MENU_LOGS
        shell_open(Util::Paths.log_dir)
      when MENU_EXIT
        @@stopping = true
        delete_icon
        Kemal.stop if Kemal.config.running
        window = @@window
        PattyUser32.destroy_window(window) unless window.null?
      end
    end

    private def open_patty
      shell_open(server_url)
    end

    private def server_url : String
      config = Config.instance.server
      host = config.bind
      host = "127.0.0.1" if {"0.0.0.0", "::", "[::]"}.includes?(host)
      host = "[#{host}]" if host.includes?(':') && !host.starts_with?('[')
      "http://#{host}:#{config.port}"
    end

    private def shell_open(target : String)
      result = PattyShell32.shell_execute(
        @@window,
        Crystal::System.to_wstr("open"),
        Crystal::System.to_wstr(target),
        Pointer(UInt16).null,
        Pointer(UInt16).null,
        SW_SHOWNORMAL,
      )
      if result.address <= 32
        Util::ActionLog.log("Windows could not open #{target}.")
      end
    end

    private def add_icon
      window = @@window
      return if window.null?

      data = notify_icon_data(window)
      unless PattyShell32.notify_icon(NIM_ADD, pointerof(data)) != 0
        Util::ActionLog.log("Windows could not add Patty to the notification area.")
      end
    end

    private def delete_icon
      window = @@window
      return if window.null?

      data = notify_icon_data(window)
      PattyShell32.notify_icon(NIM_DELETE, pointerof(data))
    end

    private def notify_icon_data(window : PattyUser32::Handle) : PattyShell32::NotifyIconData
      instance = PattyKernel32.module_handle(Pointer(UInt16).null)
      PattyShell32::NotifyIconData.new(
        size: sizeof(PattyShell32::NotifyIconData).to_u32,
        hwnd: window,
        id: ICON_ID,
        flags: NIF_MESSAGE | NIF_ICON | NIF_TIP,
        callback_message: WM_TRAY_CALLBACK,
        icon: app_icon(instance),
        tip: wide_array("Patty", 128),
        state: 0,
        state_mask: 0,
        info: StaticArray(UInt16, 256).new(0_u16),
        version: 0,
        info_title: StaticArray(UInt16, 64).new(0_u16),
        info_flags: 0,
        guid: PattyShell32::Guid.new(
          data1: 0,
          data2: 0,
          data3: 0,
          data4: StaticArray(UInt8, 8).new(0_u8),
        ),
        balloon_icon: Pointer(Void).null,
      )
    end

    private def app_icon(instance : PattyUser32::Handle) : PattyUser32::Handle
      icon = PattyUser32.load_icon(instance, Pointer(UInt16).new(ICON_ID.to_u64))
      return icon unless icon.null?
      PattyUser32.load_icon(Pointer(Void).null, Pointer(UInt16).new(IDI_APPLICATION))
    end

    private def wide_array(text : String, size : Int32)
      values = StaticArray(UInt16, 128).new(0_u16)
      text.to_utf16.each_with_index do |value, index|
        break if index >= size - 1
        values[index] = value
      end
      values
    end
  end
{% else %}
  module Patty::Windows::Tray
    def self.start
    end

    def self.stop
    end

    def self.open_existing : Bool
      false
    end
  end
{% end %}
