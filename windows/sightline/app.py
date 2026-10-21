"""The controller: camera frames in, focus changes out. Lives in the system tray."""
from __future__ import annotations

import math
import sys
import threading
import time
from typing import Optional

from pynput import keyboard, mouse
from PySide6.QtCore import QObject, QPointF, QTimer, Signal
from PySide6.QtGui import QGuiApplication
from PySide6.QtWidgets import QApplication, QMenu, QSystemTrayIcon

from . import focus
from .calibration import CalibrationSession
from .gaze import HeadAngle, HeadPose, MissCounter, OneEuroFilter, ScreenPicker, ScreenProfile
from .prefs import Preferences
from .tracker import FaceTracker, list_cameras
from .ui import GazeMarker, LiveState, PreferencesWindow, WelcomeWindow, app_icon, stylesheet


def pynput_combo(portable: str) -> str:
    """Qt's "Ctrl+Alt+G" to pynput's "<ctrl>+<alt>+g"."""
    names = {"Ctrl": "<ctrl>", "Alt": "<alt>", "Shift": "<shift>", "Meta": "<cmd>"}
    parts = portable.split("+")
    key = parts[-1]
    key = key.lower() if len(key) == 1 else f"<{key.lower()}>"
    return "+".join([names.get(p, p.lower()) for p in parts[:-1]] + [key])


class Controller(QObject):
    frame = Signal(object, bool)       # from the camera thread
    problem = Signal(object)           # from the camera thread
    clicked = Signal(int, int)         # from the input hook thread
    toggle = Signal()                  # from the shortcut thread
    cameras_found = Signal(list)

    def __init__(self, app: QApplication):
        super().__init__()
        self.app = app
        self.prefs = Preferences()
        self.state = LiveState()
        self.picker = ScreenPicker()
        self.mover = focus.FocusMover()
        self.misses = MissCounter()
        self.marker = GazeMarker()
        self.tracker = FaceTracker(lambda p, small: self.frame.emit(p, small), lambda m: self.problem.emit(m))
        self.session: Optional[CalibrationSession] = None
        self.preferences: Optional[PreferencesWindow] = None
        self.welcome: Optional[WelcomeWindow] = None
        self.camera_list: list[int] = []
        self.last_pose: Optional[tuple[HeadPose, float]] = None
        self.gaze_filter = (OneEuroFilter(0.6, 0.004), OneEuroFilter(0.6, 0.004))
        self.gaze_screen: Optional[str] = None
        self.pending: Optional[tuple[focus.Candidate, float]] = None
        self.frames = 0
        self.last_key = self.last_mouse = 0.0
        self.buttons_down = 0
        self.hotkeys: Optional[keyboard.GlobalHotKeys] = None

        self.frame.connect(self.process)
        self.problem.connect(self._camera_problem)
        self.clicked.connect(self._click)
        self.toggle.connect(lambda: self.prefs.set(active=not self.prefs.v.active))
        self.prefs.changed.connect(self.refresh)

        app.setStyleSheet(stylesheet())
        app.styleHints().colorSchemeChanged.connect(lambda _: app.setStyleSheet(stylesheet()))
        for sig in (app.screenAdded, app.screenRemoved):
            sig.connect(lambda *_: self.refresh_screens())

        self.tray = QSystemTrayIcon(app_icon(), self)
        self.menu = QMenu()
        self.menu.aboutToShow.connect(self._build_menu)
        self.tray.setContextMenu(self.menu)
        self.tray.activated.connect(lambda reason: self.open_preferences() if reason == QSystemTrayIcon.DoubleClick else None)
        self.tray.show()

        self._watch_input()
        self._bind_shortcut()
        self._sampler = QTimer(self)
        self._sampler.timeout.connect(self.mover.sample)
        self._sampler.start(250)
        self.refresh_screens()
        threading.Thread(target=lambda: self.cameras_found.emit(list_cameras()), daemon=True).start()
        self.cameras_found.connect(self._cameras)

        if not self.prefs.v.welcome_finished:
            self.open_welcome()

    # ---- Pipeline -------------------------------------------------------------------------------

    def process(self, pose: Optional[HeadPose], too_small: bool) -> None:
        self.state.pose = pose
        if self.session and self.session.active:
            self.session.add(pose, too_small)
            self.state.updated.emit()
            return
        if pose is None:
            self.picker.reset()
            self.pending = None
            self.marker.hide()
            self._publish()
            return
        if not self._running():
            self.marker.hide()
            self._publish()
            return

        now = time.monotonic()
        self.last_pose = (pose, now)
        profiles = self._active_profiles()
        if not profiles:
            self._publish()
            return
        anchors = {sid: p.shifted_anchors(pose) for sid, p in profiles.items()}
        base = sum(p.base_face_size for p in profiles.values()) / len(profiles)
        sp = pose.scaled(base)
        head = HeadAngle(sp.yaw, sp.pitch)

        facing = min(anchors, key=lambda sid: min(head.distance(a) for a in anchors[sid]) if anchors[sid] else math.inf)
        self.state.looking_at = self.picker.screen or facing
        screen = self._screen(facing)
        gaze = self._filtered_gaze(pose, screen, profiles) if screen else None
        self.state.gaze = gaze
        if self.prefs.v.show_gaze_marker and gaze:
            self.marker.show_at(self._logical(gaze))
        else:
            self.marker.hide()

        # Typing or mouse use: focus belongs where the user put it.
        typing = self.prefs.v.hold_while_typing and now - self.last_key < self.prefs.v.typing_hold_seconds
        if typing or self.buttons_down or now - self.last_mouse < 1.5:
            current = self.mover.focused_screen_id()
            if current:
                self.picker.pin(current)
            self.pending = None
            self._publish()
            return

        target_id = self.picker.step(head, anchors, self.prefs.v.switch_delay_ms / 1000, self.prefs.v.boundary, now,
                                     lambda sid: self._pupil_vote(pose, sid, profiles))
        if target_id and (target := self._screen(target_id)):
            self.state.looking_at = target_id
            self.pending = None
            near = self._gaze_on(pose, target, profiles) if self.prefs.v.follow_within_screen else None
            self.mover.bring_forward(target, near)
            self._publish()
            return

        # Within one screen: about 7 checks per second are enough for a delay of a few hundred ms.
        self.frames += 1
        if self.prefs.v.follow_within_screen and gaze and self.frames % 2 == 0:
            c = self.mover.candidate(*gaze)
            if c is None:
                self.pending = None
            elif self.pending and self.pending[0] == c:
                if now - self.pending[1] >= self.prefs.v.window_delay_ms / 1000:
                    self.pending = None
                    self.mover.commit(c)
            else:
                self.pending = (c, now)
        self._publish()

    def _running(self) -> bool:
        s = self.state.screens
        return self.prefs.v.active and bool(s) and (len(s) > 1 or self.prefs.v.follow_within_screen)

    def _active_profiles(self) -> dict[str, ScreenProfile]:
        ids = {s.id for s in self.state.screens}
        return {k: v for k, v in self.prefs.profiles().items() if k in ids}

    def _screen(self, sid: Optional[str]) -> Optional[focus.Screen]:
        return next((s for s in self.state.screens if s.id == sid), None)

    @staticmethod
    def _gaze_on(pose: HeadPose, s: focus.Screen, profiles: dict) -> Optional[tuple[float, float]]:
        p = profiles.get(s.id)
        u = p.locate(pose) if p else None
        return s.point(*u) if u else None

    def _filtered_gaze(self, pose: HeadPose, s: focus.Screen, profiles: dict) -> Optional[tuple[float, float]]:
        raw = self._gaze_on(pose, s, profiles)
        if raw is None:
            return None
        if self.gaze_screen != s.id:
            self.gaze_screen = s.id
            for f in self.gaze_filter:
                f.reset()
        t = time.monotonic()
        return self.gaze_filter[0](raw[0], t), self.gaze_filter[1](raw[1], t)

    def _pupil_vote(self, pose: HeadPose, target: str, profiles: dict) -> Optional[bool]:
        """Pupils break ties near a boundary: they vote for a screen when its pupil model puts the gaze inside it
        and the current screen's model puts it outside."""
        def margin(sid):
            p = profiles.get(sid)
            model = p.pupil_model if p else None
            f = pose.features(p.base_face_size, True) if model else None
            if not f:
                return None
            x, y = model.map(f)
            return min(x, 1 - x, y, 1 - y)

        there, here = margin(target), margin(self.picker.screen)
        if there is None or here is None:
            return None
        if there > 0.02 and here < -0.02:
            return True
        if here > 0.02 and there < -0.02:
            return False
        return None

    def _logical(self, p: tuple[float, float]) -> QPointF:
        """Physical desktop pixels to Qt's logical coordinates, per monitor."""
        s = next((s for s in self.state.screens if s.contains(*p)), None)
        qs = self.qt_screen_of(s) if s else None
        if not s or not qs:
            return QPointF(*p)
        dpr = qs.devicePixelRatio() if focus.WINDOWS else 1.0
        g = qs.geometry()
        return QPointF(g.x() + (p[0] - s.frame[0]) / dpr, g.y() + (p[1] - s.frame[1]) / dpr)

    def qt_screen_of(self, s: focus.Screen):
        return next((q for q in QGuiApplication.screens() if q.name() == s.qt_name), None)

    # ---- Clicks: misses and learning ---------------------------------------------------------------

    def _click(self, x: int, y: int) -> None:
        s = next((s for s in self.state.screens if s.contains(x, y)), None)
        if not s:
            return
        self.picker.pin(s.id)
        if not self._running() or not self.last_pose or time.monotonic() - self.last_pose[1] > 0.25:
            return
        profiles = self.prefs.profiles()
        p = profiles.get(s.id)
        if not p:
            return
        pose, unit = self.last_pose[0], s.unit(x, y)
        guess = p.locate(pose)
        if guess and self.misses.note(s.id, math.hypot(guess[0] - unit[0], guess[1] - unit[1]) > 0.35):
            self.state.unreliable.add(s.id)
        if self.prefs.v.learn_from_clicks:
            p.absorb_click(pose, unit)
            self.prefs.store_profiles(profiles)

    def _watch_input(self) -> None:
        def key(_):
            self.last_key = time.monotonic()

        def move(*_):
            self.last_mouse = time.monotonic()

        def click(x, y, button, pressed):
            self.last_mouse = time.monotonic()
            self.buttons_down = max(0, self.buttons_down + (1 if pressed else -1))
            if pressed and button == mouse.Button.left:
                self.clicked.emit(int(x), int(y))

        keyboard.Listener(on_press=key, daemon=True).start()
        mouse.Listener(on_move=move, on_click=click, on_scroll=move, daemon=True).start()

    def _bind_shortcut(self) -> None:
        if self.hotkeys:
            self.hotkeys.stop()
        try:
            self.hotkeys = keyboard.GlobalHotKeys({pynput_combo(self.prefs.v.shortcut): self.toggle.emit})
            self.hotkeys.start()
        except ValueError:
            self.hotkeys = None

    # ---- State ------------------------------------------------------------------------------

    def refresh_screens(self) -> None:
        self.state.screens = focus.screens()
        self.mover.screens = self.state.screens
        self.picker.reset()
        moved = [s.id for s in self.state.screens
                 if (p := self.prefs.profiles().get(s.id)) and p.frame and tuple(p.frame) != tuple(s.frame)]
        self.misses.suspect = set(moved)
        self.refresh()

    def refresh(self) -> None:
        if self.hotkeys is not None and getattr(self, "_bound", None) != self.prefs.v.shortcut:
            self._bound = self.prefs.v.shortcut
            self._bind_shortcut()
        self._match_camera()
        self._publish()

    def _match_camera(self) -> None:
        windows_open = any(w and w.isVisible() for w in (self.preferences, self.welcome)) or bool(self.session)
        want = self.prefs.v.active or windows_open
        if want and not self.tracker.running:
            self.tracker.start(self.prefs.v.camera_index)
        elif not want and self.tracker.running:
            self.tracker.stop()
            self.state.pose = None
            self.marker.hide()

    def _camera_problem(self, message: Optional[str]) -> None:
        self.state.camera_problem = message
        self._publish()

    def _cameras(self, found: list) -> None:
        self.camera_list = found

    def choose_camera(self, index: Optional[int]) -> None:
        if index == self.prefs.v.camera_index:
            return
        self.prefs.set(camera_index=index)
        self.tracker.stop()
        self._match_camera()

    def _summary(self) -> str:
        s, v = self.state, self.prefs.v
        if s.camera_problem:
            return s.camera_problem
        if not v.active:
            return "Paused"
        if not s.screens:
            return "Waiting for a screen"
        if len(s.screens) == 1 and not v.follow_within_screen:
            return "One screen. Turn on window focus in Preferences"
        if not any(sc.id in self.prefs.profiles() for sc in s.screens):
            return "Screens not set up"
        if s.pose is None:
            return "Watching, no face in view"
        facing = self._screen(s.looking_at)
        return f"Watching, you face {facing.name}" if facing else "Watching"

    def _publish(self) -> None:
        self.state.profiled = set(self.prefs.profiles().keys())
        self.state.summary = self._summary()
        self.tray.setToolTip(f"Sightline: {self.state.summary}")
        self.state.updated.emit()

    # ---- Menu, windows, setup ------------------------------------------------------------------

    def _build_menu(self) -> None:
        m = self.menu
        m.clear()
        info = m.addAction(self.state.summary)
        info.setEnabled(False)
        for sid in self.state.unreliable:
            s = self._screen(sid)
            if s:
                m.addAction(f"{s.name}: focus often misses").setEnabled(False)
        if self.misses.suspect:
            m.addAction("Your screens moved. Redo setup if focus lands wrong").setEnabled(False)
        m.addSeparator()
        m.addAction("Pause" if self.prefs.v.active else "Resume", lambda: self.prefs.set(active=not self.prefs.v.active))
        m.addSeparator()
        missing = [s for s in self.state.screens if s.id not in self.prefs.profiles()]
        if missing and len(missing) < len(self.state.screens):
            m.addAction(f"Set Up {', '.join(s.name for s in missing)}…", self.calibrate_new)
        m.addAction("Set Up Screens…" if len(missing) == len(self.state.screens) else "Redo Setup…", self.calibrate_all)
        m.addAction("Preferences…", self.open_preferences)
        m.addAction("Getting Started…", self.open_welcome)
        m.addSeparator()
        m.addAction("Quit Sightline", self.quit)

    def calibrate_all(self) -> None:
        self._calibrate(list(self.state.screens))

    def calibrate_new(self) -> None:
        self._calibrate([s for s in self.state.screens if s.id not in self.prefs.profiles()])

    def _calibrate(self, screens: list[focus.Screen]) -> None:
        if not screens or self.session:
            return

        def finished(results: Optional[dict]) -> None:
            self.session = None
            if results:
                profiles = self.prefs.profiles()
                profiles.update(results)
                self.prefs.store_profiles(profiles)
                for sid in results:
                    self.misses.forget(sid)
                    self.state.unreliable.discard(sid)
                self.misses.suspect -= set(results)
                self.picker.reset()
            self.refresh()

        self.session = CalibrationSession(screens, list(self.state.screens), self.prefs.profiles(), self.qt_screen_of, finished)
        self.refresh()
        self.session.start()

    def open_preferences(self) -> None:
        if self.preferences is None:
            self.preferences = PreferencesWindow(self)
        self._present(self.preferences)

    def open_welcome(self) -> None:
        if self.welcome is None:
            self.welcome = WelcomeWindow(self)
        self._present(self.welcome)

    def _present(self, w) -> None:
        w.show()
        w.raise_()
        w.activateWindow()
        self.refresh()

    def autostart(self) -> bool:
        return focus.autostart_enabled()

    def set_autostart(self, on: bool) -> None:
        command = f'"{sys.executable}"' if getattr(sys, "frozen", False) else f'"{sys.executable}" -m sightline'
        focus.set_autostart(on, command)

    def quit(self) -> None:
        self.tracker.stop()
        self.app.quit()
