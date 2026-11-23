# -*- coding: utf-8 -*-
"""Значок в трее на чистом Win32 (ctypes), без сторонних библиотек."""
from .core import *  # noqa: F401,F403 — общие константы и функции


class Tray:
    WM_TRAY = 0x0400 + 20
    WM_LBUTTONUP, WM_RBUTTONUP, WM_LBUTTONDBLCLK = 0x0202, 0x0205, 0x0203
    NIN_SELECT, NIN_KEYSELECT = 0x0400, 0x0401  # выбор значка с клавиатуры

    def __init__(self, tip, on_left, on_right, on_show=None):
        """on_show — для «покажись» от второго запуска: аварийный возврат панели."""
        W = wintypes
        self.on_left, self.on_right, self.on_show = on_left, on_right, on_show or on_left
        user32, shell32, kernel32 = ctypes.windll.user32, ctypes.windll.shell32, ctypes.windll.kernel32
        self.user32, self.shell32 = user32, shell32
        LRESULT = ctypes.c_ssize_t
        WNDPROC = ctypes.WINFUNCTYPE(LRESULT, W.HWND, W.UINT, W.WPARAM, W.LPARAM)

        class WNDCLASSW(ctypes.Structure):
            _fields_ = [("style", W.UINT), ("lpfnWndProc", WNDPROC), ("cbClsExtra", ctypes.c_int),
                        ("cbWndExtra", ctypes.c_int), ("hInstance", W.HINSTANCE), ("hIcon", W.HICON),
                        ("hCursor", W.HANDLE), ("hbrBackground", W.HBRUSH),
                        ("lpszMenuName", W.LPCWSTR), ("lpszClassName", W.LPCWSTR)]

        class NOTIFYICONDATAW(ctypes.Structure):
            _fields_ = [("cbSize", W.DWORD), ("hWnd", W.HWND), ("uID", W.UINT), ("uFlags", W.UINT),
                        ("uCallbackMessage", W.UINT), ("hIcon", W.HICON), ("szTip", W.WCHAR * 128),
                        ("dwState", W.DWORD), ("dwStateMask", W.DWORD), ("szInfo", W.WCHAR * 256),
                        ("uVersion", W.UINT), ("szInfoTitle", W.WCHAR * 64), ("dwInfoFlags", W.DWORD),
                        ("guidItem", ctypes.c_byte * 16), ("hBalloonIcon", W.HICON)]

        user32.DefWindowProcW.argtypes = [W.HWND, W.UINT, W.WPARAM, W.LPARAM]
        user32.DefWindowProcW.restype = LRESULT
        user32.CreateWindowExW.argtypes = [W.DWORD, W.LPCWSTR, W.LPCWSTR, W.DWORD, ctypes.c_int,
                                           ctypes.c_int, ctypes.c_int, ctypes.c_int, W.HWND,
                                           W.HMENU, W.HINSTANCE, W.LPVOID]
        user32.CreateWindowExW.restype = W.HWND
        user32.LoadIconW.argtypes = [W.HINSTANCE, W.LPVOID]
        user32.LoadIconW.restype = W.HICON
        user32.RegisterClassW.argtypes = [ctypes.POINTER(WNDCLASSW)]
        user32.RegisterWindowMessageW.argtypes = [W.LPCWSTR]
        user32.DestroyWindow.argtypes = [W.HWND]
        kernel32.GetModuleHandleW.argtypes = [W.LPCWSTR]
        kernel32.GetModuleHandleW.restype = W.HMODULE
        shell32.Shell_NotifyIconW.argtypes = [W.DWORD, ctypes.POINTER(NOTIFYICONDATAW)]
        shell32.Shell_NotifyIconW.restype = W.BOOL

        self.msg_taskbar = user32.RegisterWindowMessageW("TaskbarCreated")
        self._proc = WNDPROC(self._wndproc)  # держим ссылку, иначе сборщик мусора её удалит
        hinst = kernel32.GetModuleHandleW(None)
        wc = WNDCLASSW()
        wc.lpfnWndProc = self._proc
        wc.hInstance = hinst
        wc.lpszClassName = TRAY_CLASS
        user32.RegisterClassW(ctypes.byref(wc))
        self.hwnd = user32.CreateWindowExW(0, wc.lpszClassName, "DesktopPanelTray", 0,
                                           0, 0, 0, 0, None, None, hinst, None)
        if not self.hwnd:
            raise OSError("CreateWindowExW failed")
        self.nid = NOTIFYICONDATAW()
        self.nid.cbSize = ctypes.sizeof(NOTIFYICONDATAW)
        self.nid.hWnd = self.hwnd
        self.nid.uID = 1
        self.nid.uFlags = 0x1 | 0x2 | 0x4  # NIF_MESSAGE | NIF_ICON | NIF_TIP
        self.nid.uCallbackMessage = self.WM_TRAY
        self.nid.hIcon = user32.LoadIconW(None, ctypes.c_void_p(32512))  # IDI_APPLICATION
        self.nid.szTip = tip[:127]
        self._add()

    def _add(self):
        self.shell32.Shell_NotifyIconW(0, ctypes.byref(self.nid))  # NIM_ADD

    def _wndproc(self, hwnd, msg, wp, lp):
        try:
            if msg == self.WM_TRAY:
                ev = lp & 0xFFFF
                if ev in (self.WM_LBUTTONUP, self.NIN_SELECT, self.NIN_KEYSELECT):
                    self.on_left()
                elif ev == self.WM_LBUTTONDBLCLK:
                    self.on_show()  # двойной клик — гарантированно вернуть панель
                elif ev == self.WM_RBUTTONUP:
                    self.on_right()
                return 0
            if msg == WM_SHOW_PANEL:  # второй запуск программы просит показаться
                self.on_show()
                return 0
            if msg == self.msg_taskbar:  # проводник перезапустился — значок надо вернуть
                self._add()
                return 0
        except Exception:
            log_error(traceback.format_exc())
        return self.user32.DefWindowProcW(hwnd, msg, wp, lp)

    def remove(self):
        try:
            self.shell32.Shell_NotifyIconW(2, ctypes.byref(self.nid))  # NIM_DELETE
            self.user32.DestroyWindow(self.hwnd)
        except Exception:
            log_error("Не удалось убрать значок из трея:\n" + traceback.format_exc())
