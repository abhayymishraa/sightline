"""Screens, windows and keyboard focus through the Win32 API (ctypes, no extra dependencies).

All coordinates are physical pixels in the virtual desktop (the process is per-monitor DPI aware).
On other platforms the window functions do nothing, so the UI can be developed on a Mac.
"""
from __future__ import annotations

import ctypes
import os
import sys
from dataclasses import dataclass
from typing import Optional

from PySide6.QtGui import QGuiApplication

WINDOWS = sys.platform == "win32"
Rect = tuple[int, int, int, int]  # x, y, width, height


@dataclass(frozen=True)
class Screen:
    id: str
    name: str
    frame: Rect
    qt_name: str

    def contains(self, x: float, y: float) -> bool:
        fx, fy, fw, fh = self.frame
        return fx <= x < fx + fw and fy <= y < fy + fh

    def point(self, ux: float, uy: float) -> tuple[float, float]:
        fx, fy, fw, fh = self.frame
        return fx + ux * fw, fy + uy * fh

    def unit(self, x: float, y: float) -> tuple[float, float]:
        fx, fy, fw, fh = self.frame
        return (x - fx) / fw, (y - fy) / fh


def _qt_names() -> dict[str, str]:
    """Friendly monitor names (from EDID, via Qt) keyed by Qt's screen name."""
    out = {}
    for s in QGuiApplication.screens():
        friendly = " ".join(p for p in (s.manufacturer(), s.model()) if p).strip()
        out[s.name()] = friendly or s.name().replace("\\\\.\\", "")
    return out


if WINDOWS:
    from ctypes import wintypes

    user32 = ctypes.WinDLL("user32", use_last_error=True)
    dwmapi = ctypes.WinDLL("dwmapi")
    kernel32 = ctypes.WinDLL("kernel32")

    class MONITORINFOEXW(ctypes.Structure):
        _fields_ = [("cbSize", wintypes.DWORD), ("rcMonitor", wintypes.RECT), ("rcWork", wintypes.RECT),
                    ("dwFlags", wintypes.DWORD), ("szDevice", wintypes.WCHAR * 32)]

    MonitorEnumProc = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HMONITOR, wintypes.HDC, ctypes.POINTER(wintypes.RECT), wintypes.LPARAM)
    EnumWindowsProc = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)

    GWL_EXSTYLE, WS_EX_TOOLWINDOW, WS_EX_NOACTIVATE = -20, 0x80, 0x08000000
    GW_OWNER = 4
    DWMWA_EXTENDED_FRAME_BOUNDS, DWMWA_CLOAKED = 9, 14
    SW_RESTORE = 9

    def screens() -> list[Screen]:
        names = _qt_names()
        found: list[Screen] = []

        def callback(handle, _hdc, _rect, _data):
            info = MONITORINFOEXW()
            info.cbSize = ctypes.sizeof(info)
            user32.GetMonitorInfoW(handle, ctypes.byref(info))
            r = info.rcMonitor
            frame = (r.left, r.top, r.right - r.left, r.bottom - r.top)
            device = info.szDevice
            # Device names can swap after re-plugging; the friendly name plus resolution keeps profiles apart.
            sid = f"{names.get(device, device)}|{frame[2]}x{frame[3]}|{device}"
            found.append(Screen(sid, names.get(device, device), frame, device))
            return True

        user32.EnumDisplayMonitors(None, None, MonitorEnumProc(callback), 0)
        return found

    def cursor() -> tuple[int, int]:
        p = wintypes.POINT()
        user32.GetCursorPos(ctypes.byref(p))
        return p.x, p.y

    def move_cursor(x: float, y: float) -> None:
        user32.SetCursorPos(int(x), int(y))

    def foreground() -> Optional[int]:
        return user32.GetForegroundWindow() or None

    def window_pid(hwnd: int) -> int:
        pid = wintypes.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
        return pid.value

    def window_frame(hwnd: int) -> Optional[Rect]:
        r = wintypes.RECT()
        if dwmapi.DwmGetWindowAttribute(hwnd, DWMWA_EXTENDED_FRAME_BOUNDS, ctypes.byref(r), ctypes.sizeof(r)) != 0:
            if not user32.GetWindowRect(hwnd, ctypes.byref(r)):
                return None
        return r.left, r.top, r.right - r.left, r.bottom - r.top

    def _is_app_window(hwnd: int) -> bool:
        if not user32.IsWindowVisible(hwnd) or user32.IsIconic(hwnd) or user32.GetWindow(hwnd, GW_OWNER):
            return False
        ex = user32.GetWindowLongW(hwnd, GWL_EXSTYLE)
        if ex & (WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE):
            return False
        cloaked = wintypes.DWORD()
        dwmapi.DwmGetWindowAttribute(hwnd, DWMWA_CLOAKED, ctypes.byref(cloaked), ctypes.sizeof(cloaked))
        return cloaked.value == 0 and user32.GetWindowTextLengthW(hwnd) > 0

    def windows_front_to_back() -> list[tuple[int, Rect]]:
        """Visible app windows in z-order (EnumWindows walks top to bottom)."""
        own = os.getpid()
        out: list[tuple[int, Rect]] = []

        def callback(hwnd, _):
            if _is_app_window(hwnd) and window_pid(hwnd) != own:
                f = window_frame(hwnd)
                if f and f[2] > 80 and f[3] > 60:
                    out.append((hwnd, f))
            return True

        user32.EnumWindows(EnumWindowsProc(callback), 0)
        return out

    def bring_to_front(hwnd: int) -> None:
        """Windows refuses SetForegroundWindow from background apps unless the input queues are attached."""
        if user32.IsIconic(hwnd):
            user32.ShowWindow(hwnd, SW_RESTORE)
        current = user32.GetForegroundWindow()
        mine = kernel32.GetCurrentThreadId()
        theirs = user32.GetWindowThreadProcessId(current, None) if current else 0
        attached = bool(theirs) and theirs != mine and user32.AttachThreadInput(mine, theirs, True)
        try:
            user32.BringWindowToTop(hwnd)
            user32.SetForegroundWindow(hwnd)
        finally:
            if attached:
                user32.AttachThreadInput(mine, theirs, False)

    def is_valid(hwnd: int) -> bool:
        return bool(user32.IsWindow(hwnd))

    def set_autostart(enabled: bool, command: str) -> None:
        import winreg
        key = winreg.OpenKey(winreg.HKEY_CURRENT_USER, r"Software\Microsoft\Windows\CurrentVersion\Run", 0, winreg.KEY_SET_VALUE)
        with key:
            if enabled:
                winreg.SetValueEx(key, "Sightline", 0, winreg.REG_SZ, command)
            else:
                try:
                    winreg.DeleteValue(key, "Sightline")
                except FileNotFoundError:
                    pass

    def autostart_enabled() -> bool:
        import winreg
        try:
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, r"Software\Microsoft\Windows\CurrentVersion\Run") as key:
                winreg.QueryValueEx(key, "Sightline")
                return True
        except OSError:
            return False

else:  # Development on macOS: real screen geometry, no window control.
    def screens() -> list[Screen]:
        names = _qt_names()
        out = []
        for s in QGuiApplication.screens():
            g = s.geometry()
            out.append(Screen(f"{names[s.name()]}|{g.width()}x{g.height()}", names[s.name()],
                              (g.x(), g.y(), g.width(), g.height()), s.name()))
        return out

    def cursor() -> tuple[int, int]:
        from PySide6.QtGui import QCursor
        p = QCursor.pos()
        return p.x(), p.y()

    def move_cursor(x: float, y: float) -> None: ...
    def foreground() -> Optional[int]: return None
    def window_pid(hwnd: int) -> int: return 0
    def window_frame(hwnd: int) -> Optional[Rect]: return None
    def windows_front_to_back() -> list[tuple[int, Rect]]: return []
    def bring_to_front(hwnd: int) -> None: ...
    def is_valid(hwnd: int) -> bool: return False
    def set_autostart(enabled: bool, command: str) -> None: ...
    def autostart_enabled() -> bool: return False


def _area(r: Rect) -> float:
    return max(r[2], 0) * max(r[3], 0)


def _overlap(a: Rect, b: Rect) -> float:
    w = min(a[0] + a[2], b[0] + b[2]) - max(a[0], b[0])
    h = min(a[1] + a[3], b[1] + b[3]) - max(a[1], b[1])
    return max(w, 0) * max(h, 0)


@dataclass(frozen=True)
class Candidate:
    hwnd: int
    frame: Rect


class FocusMover:
    """Moves keyboard focus between screens and side-by-side windows, and remembers per screen
    which window had focus and where the pointer was, so returning to a screen restores both."""

    def __init__(self):
        self.screens: list[Screen] = []
        self._window_per_screen: dict[str, int] = {}
        self._pointer_per_screen: dict[str, tuple[int, int]] = {}

    def screen_of(self, frame: Rect) -> Optional[Screen]:
        best = max(self.screens, key=lambda s: _overlap(s.frame, frame), default=None)
        return best if best and _overlap(best.frame, frame) > 0 else None

    def focused_screen_id(self) -> Optional[str]:
        hwnd = foreground()
        f = window_frame(hwnd) if hwnd else None
        s = self.screen_of(f) if f else None
        if s:
            return s.id
        x, y = cursor()
        return next((s.id for s in self.screens if s.contains(x, y)), None)

    def sample(self) -> None:
        """Called every 250 ms."""
        x, y = cursor()
        for s in self.screens:
            if s.contains(x, y):
                self._pointer_per_screen[s.id] = (x, y)
        hwnd = foreground()
        f = window_frame(hwnd) if hwnd and window_pid(hwnd) != os.getpid() else None
        s = self.screen_of(f) if f else None
        if s:
            self._window_per_screen[s.id] = hwnd

    def bring_forward(self, screen: Screen, near: Optional[tuple[float, float]]) -> None:
        """Focus `screen`: the window under the gaze, else the last one used there, else the front one.
        The pointer follows only if it sits on another screen."""
        target: Optional[tuple[int, Rect]] = None
        hwnd = foreground()
        f = window_frame(hwnd) if hwnd else None
        already_there = f is not None and self.screen_of(f) == screen
        if not already_there:
            windows = windows_front_to_back()
            if near:
                fx, fy, fw, fh = screen.frame
                gx = min(max(near[0], fx + 1), fx + fw - 1)
                gy = min(max(near[1], fy + 1), fy + fh - 1)
                target = next(((h, r) for h, r in windows if r[0] <= gx < r[0] + r[2] and r[1] <= gy < r[1] + r[3]), None)
            remembered = self._window_per_screen.get(screen.id)
            if target is None and remembered and is_valid(remembered):
                rf = window_frame(remembered)
                if rf and self.screen_of(rf) == screen:
                    target = (remembered, rf)
            if target is None:
                target = next(((h, r) for h, r in windows if self.screen_of(r) == screen), None)
            if target:
                bring_to_front(target[0])
                self._window_per_screen[screen.id] = target[0]

        x, y = cursor()
        if screen.contains(x, y):
            return
        remembered_pointer = self._pointer_per_screen.get(screen.id)
        if target:
            wx, wy, ww, wh = target[1]
            if remembered_pointer and wx <= remembered_pointer[0] < wx + ww and wy <= remembered_pointer[1] < wy + wh:
                move_cursor(*remembered_pointer)
                return
            move_cursor(wx + ww / 2, wy + wh / 2)
        elif remembered_pointer and screen.contains(*remembered_pointer):
            move_cursor(*remembered_pointer)
        else:
            sx, sy, sw, sh = screen.frame
            move_cursor(sx + sw / 2, sy + sh / 2)

    def candidate(self, x: float, y: float) -> Optional[Candidate]:
        """The front window under (x, y); points near a window edge do not count."""
        for hwnd, r in windows_front_to_back():
            if r[0] <= x < r[0] + r[2] and r[1] <= y < r[1] + r[3]:
                margin = min(min(r[2], r[3]) * 0.1, 60)
                inside = r[0] + margin <= x < r[0] + r[2] - margin and r[1] + margin <= y < r[1] + r[3] - margin
                return Candidate(hwnd, r) if inside else None
        return None

    def commit(self, c: Candidate) -> None:
        """Focus a side-by-side window. A window that sits mostly behind the focused one never comes forward."""
        current = foreground()
        if current == c.hwnd:
            return
        cf = window_frame(current) if current else None
        if cf and _overlap(cf, c.frame) > 0.1 * min(_area(cf), _area(c.frame)):
            return
        bring_to_front(c.hwnd)
        s = self.screen_of(c.frame)
        if s:
            self._window_per_screen[s.id] = c.hwnd
