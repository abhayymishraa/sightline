"""Qt widgets: design tokens, shared components, the screen map, gaze marker, Preferences and Getting Started."""
from __future__ import annotations

import sys
from typing import Callable, Optional

from PySide6.QtCore import (Property, QEasingCurve, QObject, QPointF, QPropertyAnimation, QRectF, QSize, Qt, QUrl,
                            Signal)
from PySide6.QtGui import (QColor, QDesktopServices, QGuiApplication, QIcon, QKeySequence, QPainter, QPen)
from PySide6.QtWidgets import (QAbstractButton, QComboBox, QFrame, QHBoxLayout, QKeySequenceEdit, QLabel, QPushButton,
                               QScrollArea, QSlider, QStackedWidget, QVBoxLayout, QWidget)

from .paths import asset

# Design tokens, from the accretion frontend palette.
LIGHT = dict(brand="#1E9DF1", on_brand="#FFFFFF", tint="#E3ECF6", caution="#B42318", backdrop="#F7F8F8",
             panel="#FFFFFF", hairline="#E1EAEF", text="#0F1419", muted="#52585D", faint="#8B9196")
DARK = dict(brand="#1C9CF0", on_brand="#FFFFFF", tint="#061622", caution="#F97066", backdrop="#000000",
            panel="#17181C", hairline="#242628", text="#E7E9EA", muted="#72767A", faint="#55595D")
FONT = "Segoe UI Variable Text" if sys.platform == "win32" else ".AppleSystemUIFont"


def tokens() -> dict:
    return DARK if QGuiApplication.styleHints().colorScheme() == Qt.ColorScheme.Dark else LIGHT


def stylesheet() -> str:
    t = tokens()
    return f"""
    * {{ font-family: "{FONT}"; color: {t['text']}; }}
    QWidget#window, QScrollArea, QWidget#scroll {{ background: {t['backdrop']}; }}
    QWidget#content {{ background: {t['panel']}; }}
    QFrame#card {{ background: {t['panel']}; border: 1px solid {t['hairline']}; border-radius: 12px; }}
    QFrame#divider {{ background: {t['hairline']}; max-height: 1px; min-height: 1px; border: none; }}
    QLabel {{ background: transparent; }}
    QLabel#h1 {{ font-size: 24px; font-weight: 600; }}
    QLabel#h2 {{ font-size: 13px; font-weight: 600; }}
    QLabel#title {{ font-size: 13px; font-weight: 500; }}
    QLabel#detail {{ font-size: 12px; color: {t['muted']}; }}
    QLabel#faint {{ font-size: 11px; color: {t['faint']}; }}
    QLabel#value {{ font-size: 12px; font-weight: 600; color: {t['brand']}; }}
    QLabel#brand {{ font-size: 12.5px; font-weight: 500; color: {t['brand']}; }}
    QLabel#caution {{ font-size: 12.5px; color: {t['caution']}; }}
    QLabel#help {{ color: {t['faint']}; font-size: 12px; }}
    QPushButton {{ font-size: 13px; border-radius: 8px; padding: 0 16px; min-height: 32px; }}
    QPushButton#primary {{ background: {t['brand']}; color: {t['on_brand']}; font-weight: 600; border: none; }}
    QPushButton#primary:pressed {{ padding-top: 1px; }}
    QPushButton#primary:disabled {{ background: {t['hairline']}; color: {t['faint']}; }}
    QPushButton#secondary {{ background: {t['panel']}; border: 1px solid {t['hairline']}; font-weight: 500; }}
    QPushButton#secondary:pressed {{ padding-top: 1px; }}
    QSlider::groove:horizontal {{ height: 4px; background: {t['hairline']}; border-radius: 2px; }}
    QSlider::sub-page:horizontal {{ background: {t['brand']}; border-radius: 2px; }}
    QSlider::handle:horizontal {{ background: #FFFFFF; border: 1px solid {t['hairline']}; width: 18px; height: 18px;
                                  margin: -8px 0; border-radius: 9px; }}
    QComboBox, QKeySequenceEdit {{ background: {t['panel']}; border: 1px solid {t['hairline']}; border-radius: 7px;
                                   padding: 4px 10px; min-height: 22px; }}
    QScrollBar:vertical {{ width: 8px; background: transparent; }}
    QScrollBar::handle:vertical {{ background: {t['hairline']}; border-radius: 4px; min-height: 30px; }}
    QScrollBar::add-line, QScrollBar::sub-line {{ height: 0; }}
    """


def label(text: str, name: str = "detail", wrap: bool = True) -> QLabel:
    l = QLabel(text)
    l.setObjectName(name)
    l.setWordWrap(wrap)
    return l


def divider() -> QFrame:
    f = QFrame()
    f.setObjectName("divider")
    return f


def card(*rows: QWidget) -> QFrame:
    f = QFrame()
    f.setObjectName("card")
    box = QVBoxLayout(f)
    box.setContentsMargins(0, 0, 0, 0)
    box.setSpacing(0)
    for i, row in enumerate(rows):
        if i:
            box.addWidget(divider())
        box.addWidget(row)
    return f


def button(text: str, primary: bool, on_click: Callable) -> QPushButton:
    b = QPushButton(text)
    b.setObjectName("primary" if primary else "secondary")
    b.setCursor(Qt.PointingHandCursor)
    b.clicked.connect(on_click)
    return b


def app_icon() -> QIcon:
    return QIcon(str(asset("icon.png")))


class Switch(QAbstractButton):
    """An iOS-style switch. The knob slides in 150 ms; a click is the only trigger, so it may animate."""

    def __init__(self, checked: bool = False):
        super().__init__()
        self.setCheckable(True)
        self.setChecked(checked)
        self.setCursor(Qt.PointingHandCursor)
        self.setFixedSize(38, 22)
        self._offset = 1.0 if checked else 0.0
        self._anim = QPropertyAnimation(self, b"offset", self)
        self._anim.setDuration(150)
        self._anim.setEasingCurve(QEasingCurve.OutCubic)
        self.toggled.connect(self._slide)

    def _slide(self, on: bool) -> None:
        self._anim.stop()
        self._anim.setEndValue(1.0 if on else 0.0)
        self._anim.start()

    def get_offset(self) -> float:
        return self._offset

    def set_offset(self, v: float) -> None:
        self._offset = v
        self.update()

    offset = Property(float, get_offset, set_offset)

    def paintEvent(self, _):
        t = tokens()
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        off, on = QColor(t["hairline"]), QColor(t["brand"])
        track = QColor(
            int(off.red() + (on.red() - off.red()) * self._offset),
            int(off.green() + (on.green() - off.green()) * self._offset),
            int(off.blue() + (on.blue() - off.blue()) * self._offset),
        )
        p.setPen(Qt.NoPen)
        p.setBrush(track)
        p.drawRoundedRect(QRectF(0, 0, 38, 22), 11, 11)
        p.setBrush(QColor("#FFFFFF"))
        p.drawEllipse(QRectF(2 + 16 * self._offset, 2, 18, 18))

    def sizeHint(self) -> QSize:
        return QSize(38, 22)


def switch_row(title: str, detail: str, value: bool, on_change: Callable[[bool], None], help_text: str = "") -> QWidget:
    w = QWidget()
    row = QHBoxLayout(w)
    row.setContentsMargins(14, 12, 14, 12)
    text = QVBoxLayout()
    text.setSpacing(2)
    head = QHBoxLayout()
    head.setSpacing(6)
    head.addWidget(label(title, "title", wrap=False))
    if help_text:
        h = label("ⓘ", "help", wrap=False)
        h.setToolTip(help_text)
        head.addWidget(h)
    head.addStretch()
    text.addLayout(head)
    text.addWidget(label(detail))
    row.addLayout(text, 1)
    s = Switch(value)
    s.toggled.connect(on_change)
    row.addWidget(s, 0, Qt.AlignVCenter)
    return w


def slider_row(title: str, detail: str, value: float, lo: float, hi: float, step: float,
               fmt: Callable[[float], str], on_change: Callable[[float], None], help_text: str = "") -> QWidget:
    w = QWidget()
    box = QVBoxLayout(w)
    box.setContentsMargins(14, 12, 14, 12)
    box.setSpacing(8)
    head = QHBoxLayout()
    head.addWidget(label(title, "title", wrap=False))
    if help_text:
        h = label("ⓘ", "help", wrap=False)
        h.setToolTip(help_text)
        head.addWidget(h)
    head.addStretch()
    shown = label(fmt(value), "value", wrap=False)
    head.addWidget(shown)
    box.addLayout(head)
    s = QSlider(Qt.Horizontal)
    steps = round((hi - lo) / step)
    s.setRange(0, steps)
    s.setValue(round((value - lo) / step))
    s.setCursor(Qt.PointingHandCursor)

    def moved(i: int):
        v = lo + i * step
        shown.setText(fmt(v))
        on_change(v)

    s.valueChanged.connect(moved)
    box.addWidget(s)
    box.addWidget(label(detail))
    return w


def section(title: str, body: QWidget) -> QWidget:
    w = QWidget()
    box = QVBoxLayout(w)
    box.setContentsMargins(0, 0, 0, 0)
    box.setSpacing(8)
    box.addWidget(label(title, "h2", wrap=False))
    box.addWidget(body)
    return w


class LiveState(QObject):
    """What the windows show. Written by the controller on the UI thread."""
    updated = Signal()

    def __init__(self):
        super().__init__()
        self.screens = []
        self.looking_at: Optional[str] = None
        self.gaze: Optional[tuple[float, float]] = None
        self.pose = None
        self.camera_problem: Optional[str] = None
        self.summary = ""
        self.unreliable: set[str] = set()
        self.profiled: set[str] = set()


class ScreenMap(QWidget):
    """The connected screens, scaled; the one you face is highlighted and the dot is the estimated gaze."""

    def __init__(self, state: LiveState, height: int = 120):
        super().__init__()
        self.state = state
        self.setMinimumHeight(height)
        state.updated.connect(self.update)

    def paintEvent(self, _):
        t = tokens()
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        screens = self.state.screens
        if not screens:
            p.setPen(QColor(t["faint"]))
            p.drawText(self.rect(), Qt.AlignCenter, "No screens found")
            return
        x0 = min(s.frame[0] for s in screens)
        y0 = min(s.frame[1] for s in screens)
        x1 = max(s.frame[0] + s.frame[2] for s in screens)
        y1 = max(s.frame[1] + s.frame[3] for s in screens)
        scale = min(self.width() / (x1 - x0), self.height() / (y1 - y0)) * 0.92
        ox = (self.width() - (x1 - x0) * scale) / 2
        oy = (self.height() - (y1 - y0) * scale) / 2
        for s in screens:
            facing = s.id == self.state.looking_at
            r = QRectF(ox + (s.frame[0] - x0) * scale + 2, oy + (s.frame[1] - y0) * scale + 2,
                       s.frame[2] * scale - 4, s.frame[3] * scale - 4)
            p.setPen(QPen(QColor(t["brand"] if facing else t["hairline"]), 1.5 if facing else 1))
            p.setBrush(QColor(t["tint"] if facing else t["backdrop"]))
            p.drawRoundedRect(r, 6, 6)
            p.setPen(QColor(t["brand"] if facing else t["muted"]))
            name = s.name if s.id in self.state.profiled else f"{s.name}\nNot set up"
            p.drawText(r.adjusted(4, 4, -4, -4), Qt.AlignCenter | Qt.TextWordWrap, name)
        if self.state.gaze:
            gx, gy = self.state.gaze
            c = QPointF(ox + (gx - x0) * scale, oy + (gy - y0) * scale)
            p.setPen(QPen(QColor("#FFFFFF"), 1.5))
            p.setBrush(QColor(t["brand"]))
            p.drawEllipse(c, 4, 4)


class GazeMarker(QWidget):
    """A click-through dot at the estimated gaze point."""

    def __init__(self):
        super().__init__(None, Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.Tool
                         | Qt.WindowTransparentForInput | Qt.WindowDoesNotAcceptFocus)
        self.setAttribute(Qt.WA_TranslucentBackground)
        self.setAttribute(Qt.WA_ShowWithoutActivating)
        self.resize(22, 22)

    def paintEvent(self, _):
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        c = QColor(tokens()["brand"])
        c.setAlphaF(0.6)
        p.setBrush(c)
        p.setPen(QPen(QColor(255, 255, 255, 230), 2))
        p.drawEllipse(QRectF(1, 1, 20, 20))

    def show_at(self, logical: QPointF) -> None:
        self.move(int(logical.x() - 11), int(logical.y() - 11))
        if not self.isVisible():
            self.show()


def shortcut_field(current: str, on_change: Callable[[str], None]) -> QKeySequenceEdit:
    edit = QKeySequenceEdit(QKeySequence(current))
    edit.setMaximumSequenceLength(1)
    edit.setFixedWidth(150)

    def done():
        seq = edit.keySequence().toString(QKeySequence.PortableText)
        if seq and any(m in seq for m in ("Ctrl", "Alt", "Meta")):
            on_change(seq)
        else:
            edit.setKeySequence(QKeySequence(current))

    edit.editingFinished.connect(done)
    return edit


class PreferencesWindow(QWidget):
    def __init__(self, ctl):
        super().__init__()
        self.ctl, v = ctl, ctl.prefs.v
        self.setWindowTitle("Sightline Preferences")
        self.setWindowIcon(app_icon())
        self.setObjectName("window")
        self.resize(560, 700)
        set_ = ctl.prefs.set

        content = QWidget()
        content.setObjectName("scroll")
        box = QVBoxLayout(content)
        box.setContentsMargins(24, 24, 24, 24)
        box.setSpacing(22)

        # Status
        head = QWidget()
        hl = QHBoxLayout(head)
        hl.setContentsMargins(14, 14, 14, 14)
        icon = QLabel()
        icon.setPixmap(app_icon().pixmap(40, 40))
        hl.addWidget(icon)
        names = QVBoxLayout()
        names.addWidget(label("Sightline", "h2", wrap=False))
        self.summary = label("", "detail", wrap=False)
        names.addWidget(self.summary)
        hl.addLayout(names, 1)
        self.active = Switch(v.active)
        self.active.toggled.connect(lambda on: set_(active=on))
        hl.addWidget(self.active)
        map_row = QWidget()
        ml = QVBoxLayout(map_row)
        ml.setContentsMargins(14, 14, 14, 10)
        ml.addWidget(ScreenMap(ctl.state, 110))
        self.reading = label("", "faint", wrap=False)
        ml.addWidget(self.reading)
        box.addWidget(card(head, map_row))

        box.addWidget(section("Between screens", card(
            slider_row("Switch delay", "Shorter looks than this do not switch.", v.switch_delay_ms, 100, 1000, 50,
                       lambda x: f"{int(x)} ms", lambda x: set_(switch_delay_ms=x),
                       "Time you must face another screen before focus moves to it. Short is quick; long ignores brief looks."),
            slider_row("Turn amount", "How far your head turns before the next screen wins.", v.boundary, 0.2, 0.8, 0.05,
                       lambda x: f"{round(x * 100)}%", lambda x: set_(boundary=x),
                       "The boundary between two screens, as a share of the distance between their nearest setup spots."),
        )))
        box.addWidget(section("On one screen", card(
            switch_row("Follow windows", "Windows side by side on the screen you face.", v.follow_within_screen,
                       lambda on: set_(follow_within_screen=on),
                       "On the screen you face, focus moves between side-by-side windows. Windows that overlap never switch."),
            slider_row("Window delay", "Look time before a window gets focus.", v.window_delay_ms, 100, 1000, 50,
                       lambda x: f"{int(x)} ms", lambda x: set_(window_delay_ms=x)),
        )))
        box.addWidget(section("Typing and learning", card(
            switch_row("Hold focus while typing", "Keystrokes stay where you type.", v.hold_while_typing,
                       lambda on: set_(hold_while_typing=on)),
            slider_row("Hold time", "Time after the last keystroke.", v.typing_hold_seconds, 0.5, 5, 0.25,
                       lambda x: f"{x:g} s", lambda x: set_(typing_hold_seconds=x)),
            switch_row("Learn from clicks", "Clicks fine-tune the setup.", v.learn_from_clicks,
                       lambda on: set_(learn_from_clicks=on),
                       "You look where you click, so each click on the screen you face becomes a new reference point."),
            switch_row("Show gaze marker", "A rough mark of where Sightline thinks you look.", v.show_gaze_marker,
                       lambda on: set_(show_gaze_marker=on)),
        )))

        cam = QWidget()
        cl = QHBoxLayout(cam)
        cl.setContentsMargins(14, 12, 14, 12)
        ct = QVBoxLayout()
        ct.addWidget(label("Camera", "title", wrap=False))
        ct.addWidget(label("Pick the camera in front of you."))
        cl.addLayout(ct, 1)
        self.cameras = QComboBox()
        self.cameras.setFixedWidth(170)
        self.cameras.currentIndexChanged.connect(self._camera_picked)
        cl.addWidget(self.cameras)
        setup = QWidget()
        sl = QHBoxLayout(setup)
        sl.setContentsMargins(14, 12, 14, 12)
        st = QVBoxLayout()
        st.addWidget(label("Screen setup", "title", wrap=False))
        st.addWidget(label("Redo it after you move a screen or your laptop."))
        sl.addLayout(st, 1)
        self.setup_new = button("Set Up New…", False, ctl.calibrate_new)
        sl.addWidget(self.setup_new)
        self.setup_all = button("Set Up…", True, ctl.calibrate_all)
        sl.addWidget(self.setup_all)
        box.addWidget(section("Camera and setup", card(cam, setup)))

        short = QWidget()
        kl = QHBoxLayout(short)
        kl.setContentsMargins(14, 12, 14, 12)
        kt = QVBoxLayout()
        kt.addWidget(label("Pause shortcut", "title", wrap=False))
        kt.addWidget(label("Works from any app."))
        kl.addLayout(kt, 1)
        kl.addWidget(shortcut_field(v.shortcut, lambda s: set_(shortcut=s)))
        box.addWidget(section("General", card(
            short,
            switch_row("Open at login", "Start Sightline when you sign in.", ctl.autostart(), ctl.set_autostart),
        )))
        foot = label("Sightline reads camera frames in memory. It never stores or sends them.", "faint")
        foot.setAlignment(Qt.AlignCenter)
        box.addWidget(foot)

        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setFrameShape(QFrame.NoFrame)
        scroll.setWidget(content)
        outer = QVBoxLayout(self)
        outer.setContentsMargins(0, 0, 0, 0)
        outer.addWidget(scroll)

        ctl.state.updated.connect(self.refresh)
        ctl.cameras_found.connect(self.fill_cameras)
        self.fill_cameras(ctl.camera_list)
        self.refresh()

    def fill_cameras(self, indices: list[int]) -> None:
        self.cameras.blockSignals(True)
        self.cameras.clear()
        for i in indices or [0]:
            self.cameras.addItem(f"Camera {i + 1}", i)
        current = self.ctl.prefs.v.camera_index or 0
        self.cameras.setCurrentIndex(max(self.cameras.findData(current), 0))
        self.cameras.blockSignals(False)

    def _camera_picked(self, _):
        self.ctl.choose_camera(self.cameras.currentData())

    def refresh(self) -> None:
        s = self.ctl.state
        self.summary.setText(s.summary)
        self.active.blockSignals(True)
        self.active.setChecked(self.ctl.prefs.v.active)
        self.active.blockSignals(False)
        self.reading.setText(f"Yaw {s.pose.yaw:+.1f}°   Pitch {s.pose.pitch:+.1f}°   Live from the camera" if s.pose else "")
        profiled = sum(1 for sc in s.screens if sc.id in s.profiled)
        self.setup_all.setText("Set Up…" if profiled == 0 else "Redo Setup…")
        self.setup_new.setVisible(0 < profiled < len(s.screens))


class WelcomeWindow(QWidget):
    STEPS = ["Hello", "Camera", "Screens", "Tune", "Test", "Done"]

    def __init__(self, ctl):
        super().__init__()
        self.ctl = ctl
        self.setWindowTitle("Getting Started")
        self.setWindowIcon(app_icon())
        self.setObjectName("window")
        self.setFixedSize(780, 540)
        self.step = 0

        outer = QHBoxLayout(self)
        outer.setContentsMargins(0, 0, 0, 0)
        outer.setSpacing(0)
        side = QWidget()
        side.setObjectName("window")
        side.setFixedWidth(200)
        sl = QVBoxLayout(side)
        sl.setContentsMargins(22, 22, 22, 22)
        brand = QHBoxLayout()
        icon = QLabel()
        icon.setPixmap(app_icon().pixmap(28, 28))
        brand.addWidget(icon)
        brand.addWidget(label("Sightline", "h2", wrap=False))
        brand.addStretch()
        sl.addLayout(brand)
        sl.addSpacing(18)
        self.markers: list[QLabel] = []
        for i, name in enumerate(self.STEPS):
            m = label(f"{i + 1}   {name}", "detail", wrap=False)
            m.setMinimumHeight(30)
            self.markers.append(m)
            sl.addWidget(m)
        sl.addStretch()
        sl.addWidget(label("About two minutes", "faint"))
        outer.addWidget(side)

        main = QWidget()
        main.setObjectName("content")
        ml = QVBoxLayout(main)
        ml.setContentsMargins(36, 36, 36, 20)
        self.pages = QStackedWidget()
        for page in (self._hello(), self._camera(), self._screens(), self._tune(), self._test(), self._done()):
            self.pages.addWidget(page)
        ml.addWidget(self.pages, 1)
        foot = QHBoxLayout()
        self.back = button("Back", False, lambda: self.go(-1))
        foot.addWidget(self.back)
        foot.addStretch()
        self.next = button("Begin", True, self._next)
        foot.addWidget(self.next)
        ml.addLayout(foot)
        outer.addWidget(main, 1)

        ctl.state.updated.connect(self.refresh)
        self.refresh()

    def _page(self, title: str, detail: str) -> tuple[QWidget, QVBoxLayout]:
        w = QWidget()
        box = QVBoxLayout(w)
        box.setContentsMargins(0, 0, 0, 0)
        box.setSpacing(20)
        head = QVBoxLayout()
        head.setSpacing(8)
        head.addWidget(label(title, "h1", wrap=False))
        d = label(detail, "detail")
        d.setStyleSheet("font-size: 13.5px;")
        head.addWidget(d)
        box.addLayout(head)
        return w, box

    def _hello(self) -> QWidget:
        w, box = self._page("Type where you look",
                            "Sightline uses your webcam to see which screen or window you face, and moves keyboard focus there. No more clicking before you type.")
        for title, detail in (("Face it", "Turn to the screen or window you want."),
                              ("Sightline sees it", "The camera reads your head angle and pupils."),
                              ("Type", "Your keystrokes land there. No click.")):
            row = QVBoxLayout()
            row.setSpacing(2)
            row.addWidget(label(title, "title", wrap=False))
            row.addWidget(label(detail))
            box.addLayout(row)
        box.addWidget(label(f"Press {self.ctl.prefs.v.shortcut} or use the tray icon to pause.", "brand"))
        box.addStretch()
        return w

    def _camera(self) -> QWidget:
        w, box = self._page("Allow the camera",
                            "Windows lets you turn camera access off for desktop apps. Sightline needs it on to see which way you face.")
        self.camera_status = label("", "brand")
        box.addWidget(self.camera_status)
        box.addWidget(button("Open Camera Privacy Settings", False,
                             lambda: QDesktopServices.openUrl(QUrl("ms-settings:privacy-webcam"))), 0, Qt.AlignLeft)
        box.addWidget(label("Frames stay in memory. Nothing is stored or sent.", "faint"))
        box.addStretch()
        return w

    def _screens(self) -> QWidget:
        w, box = self._page("Show Sightline your screens", "Sightline learns where each screen sits, as seen from your chair.")
        for line in ("Each screen turns bright and shows a dot.",
                     "Press Space. Follow the dot with head and eyes, then with eyes only.",
                     "About 30 seconds per screen.", "Sit as you normally work."):
            box.addWidget(label(f"•  {line}", "title"))
        row = QHBoxLayout()
        self.start_setup = button("Start Setup", True, self.ctl.calibrate_all)
        row.addWidget(self.start_setup)
        self.setup_status = label("", "brand", wrap=False)
        row.addWidget(self.setup_status)
        row.addStretch()
        box.addLayout(row)
        box.addStretch()
        return w

    def _tune(self) -> QWidget:
        w, box = self._page("Tune the feel", "The defaults work for most people. Preferences can change them later.")
        v, set_ = self.ctl.prefs.v, self.ctl.prefs.set
        box.addWidget(card(
            switch_row("Follow windows", "Not only screens: side-by-side windows too.", v.follow_within_screen,
                       lambda on: set_(follow_within_screen=on)),
            switch_row("Hold focus while typing", "Keystrokes stay where you type.", v.hold_while_typing,
                       lambda on: set_(hold_while_typing=on)),
            switch_row("Learn from clicks", "Clicks fine-tune the setup.", v.learn_from_clicks,
                       lambda on: set_(learn_from_clicks=on)),
            slider_row("Switch delay", "Shorter looks than this do not switch.", v.switch_delay_ms, 100, 1000, 50,
                       lambda x: f"{int(x)} ms", lambda x: set_(switch_delay_ms=x)),
        ))
        box.addStretch()
        return w

    def _test(self) -> QWidget:
        w, box = self._page("Try it now", "Look from screen to screen. The map marks the screen you face, and the dot shows about where you look.")
        box.addWidget(card(_padded(ScreenMap(self.ctl.state, 170))))
        self.test_status = label("", "brand")
        box.addWidget(self.test_status)
        box.addStretch()
        return w

    def _done(self) -> QWidget:
        w, box = self._page("Sightline runs from the tray", "Find it in the notification area, next to the clock.")
        box.addWidget(card(
            _padded(label("Click the tray icon to pause, redo setup or open Preferences.", "title")),
            _padded(label(f"Press {self.ctl.prefs.v.shortcut} in any app to pause or resume.", "title")),
        ))
        box.addWidget(card(switch_row("Open at login", "Start Sightline when you sign in.", self.ctl.autostart(),
                                      self.ctl.set_autostart)))
        box.addWidget(label("Camera frames stay in memory on this PC. Nothing is stored or sent.", "faint"))
        box.addStretch()
        return w

    def _next(self) -> None:
        if self.step == len(self.STEPS) - 1:
            self.ctl.prefs.set(welcome_finished=True)
            self.close()
        else:
            self.go(1)

    def go(self, delta: int) -> None:
        self.step = max(0, min(len(self.STEPS) - 1, self.step + delta))
        self.pages.setCurrentIndex(self.step)
        self.refresh()

    def refresh(self) -> None:
        t, s = tokens(), self.ctl.state
        for i, m in enumerate(self.markers):
            done, now = i < self.step, i == self.step
            m.setText(f"{'✓' if done else i + 1}   {self.STEPS[i]}")
            m.setStyleSheet(f"font-size: 13px; color: {t['brand'] if now else t['muted']}; font-weight: {600 if now else 400};")
        self.back.setVisible(self.step > 0)
        all_set = bool(s.screens) and all(sc.id in s.profiled for sc in s.screens)
        self.next.setText({0: "Begin", len(self.STEPS) - 1: "Finish"}.get(self.step, "Later" if self.step == 2 and not all_set else "Next"))
        self.camera_status.setText(s.camera_problem or ("Face in view. The camera works." if s.pose else "Looking for a face…"))
        self.start_setup.setEnabled(s.pose is not None)
        self.start_setup.setText("Redo Setup" if all_set else "Start Setup")
        self.setup_status.setText("Every screen is set up" if all_set else "")
        self.test_status.setText(s.summary if all_set else "Set up your screens first (step 3).")


def _padded(w: QWidget) -> QWidget:
    holder = QWidget()
    box = QVBoxLayout(holder)
    box.setContentsMargins(16, 14, 16, 14)
    box.addWidget(w)
    return holder
