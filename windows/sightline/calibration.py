"""Screen setup: one bright full-screen overlay per screen, a dot to follow, then a few dots for the eyes only."""
from __future__ import annotations

import math
import time
from typing import Callable, Optional

from PySide6.QtCore import QPointF, QRectF, Qt, QVariantAnimation, QEasingCurve
from PySide6.QtGui import QColor, QFont, QPainter, QPen
from PySide6.QtWidgets import QWidget

from .focus import Screen
from .gaze import HeadAngle, HeadPose, LookSample, ScreenProfile, trimmed
from .ui import FONT

EYE_SPOTS = [(0.15, 0.5), (0.85, 0.5), (0.5, 0.15), (0.5, 0.85)]
BRAND = QColor("#1E9DF1")
INK = QColor("#0F1419")
MUTED = QColor("#52585D")
CAUTION = QColor("#B42318")


def spots_for(s: Screen, every: list[Screen]) -> list[tuple[float, float]]:
    """Spots where precision matters: along edges shared with neighbouring screens, plus the centre.
    A screen without neighbours gets four inner corners instead."""
    fx, fy, fw, fh = s.frame

    def spread(lo, hi):
        return [min(max(lo + (hi - lo) * t, 0.04), 0.96) for t in ((0.5,) if hi - lo < 0.3 else (0.25, 0.5, 0.75))]

    pts = [(0.5, 0.5)]
    for n in every:
        if n.id == s.id:
            continue
        gx, gy, gw, gh = n.frame
        y_lo, y_hi = (max(fy, gy) - fy) / fh, (min(fy + fh, gy + gh) - fy) / fh
        x_lo, x_hi = (max(fx, gx) - fx) / fw, (min(fx + fw, gx + gw) - fx) / fw
        if abs(gx - (fx + fw)) <= 2 and y_hi > y_lo:
            pts += [(0.97, y) for y in spread(y_lo, y_hi)]
        if abs((gx + gw) - fx) <= 2 and y_hi > y_lo:
            pts += [(0.03, y) for y in spread(y_lo, y_hi)]
        if abs(gy - (fy + fh)) <= 2 and x_hi > x_lo:
            pts += [(x, 0.96) for x in spread(x_lo, x_hi)]
        if abs((gy + gh) - fy) <= 2 and x_hi > x_lo:
            pts += [(x, 0.04) for x in spread(x_lo, x_hi)]
    if len(pts) == 1:
        pts += [(0.2, 0.2), (0.8, 0.2), (0.2, 0.8), (0.8, 0.8)]
    unique: list[tuple[float, float]] = []
    for p in pts:
        if all(math.hypot(p[0] - q[0], p[1] - q[1]) >= 0.1 for q in unique):
            unique.append(p)
    return unique


def true_median(v: list[float]) -> float:
    s = sorted(v)
    n = len(s)
    return s[n // 2] if n % 2 else (s[n // 2 - 1] + s[n // 2]) / 2


class Overlay(QWidget):
    """The always-light setup screen: a bright screen lights the face, which helps the camera."""

    def __init__(self, on_key: Callable[[int], None]):
        super().__init__(None, Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint)
        self.on_key = on_key
        self.phase = "ready"   # ready | running | failed
        self.title = self.subtitle = self.screen_label = ""
        self.spot = (0.5, 0.5)
        self.shown_spot = QPointF(0.5, 0.5)
        self.spot_progress = 0.0
        self.progress = 0.0
        self._move = QVariantAnimation(self)
        self._move.setDuration(450)
        self._move.setEasingCurve(QEasingCurve.InOutQuart)
        self._move.valueChanged.connect(self._moved)

    def _moved(self, v: QPointF) -> None:
        self.shown_spot = v
        self.update()

    def move_spot(self, spot: tuple[float, float]) -> None:
        self.spot = spot
        self._move.stop()
        self._move.setStartValue(self.shown_spot)
        self._move.setEndValue(QPointF(*spot))
        self._move.start()

    def keyPressEvent(self, e) -> None:
        self.on_key(e.key())

    def paintEvent(self, _):
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        w, h = self.width(), self.height()
        p.fillRect(self.rect(), QColor("#F7F8F8"))
        p.fillRect(QRectF(0, h - 3, w * self.progress, 3), BRAND)

        running = self.phase == "running"
        cy = h / 2 + (110 if running else 0)
        if running:
            c = QPointF(self.shown_spot.x() * w, self.shown_spot.y() * h)
            ring = QColor(BRAND)
            ring.setAlphaF(0.15)
            p.setPen(QPen(ring, 3))
            p.drawEllipse(c, 20, 20)
            p.setPen(QPen(BRAND, 3, Qt.SolidLine, Qt.RoundCap))
            p.drawArc(QRectF(c.x() - 20, c.y() - 20, 40, 40), 90 * 16, int(-360 * 16 * self.spot_progress))
            p.setPen(Qt.NoPen)
            p.setBrush(BRAND)
            p.drawEllipse(c, 8, 8)
            p.setBrush(QColor("#FFFFFF"))
            p.drawEllipse(c, 2.5, 2.5)

        def text(y, s, size, weight, color):
            f = QFont(FONT)
            f.setPixelSize(size)
            f.setWeight(weight)
            p.setFont(f)
            p.setPen(color)
            p.drawText(QRectF(40, y, w - 80, size * 3), Qt.AlignHCenter | Qt.AlignTop | Qt.TextWordWrap, s)

        if not running:
            text(cy - 70, self.screen_label, 13, QFont.Medium, MUTED)
        text(cy - 40, self.title, 17 if running else 26, QFont.DemiBold, CAUTION if self.phase == "failed" else INK)
        text(cy + 4, self.subtitle, 13 if running else 15, QFont.Normal, MUTED)
        if not running:
            text(cy + 60, "Space  start        Esc  cancel", 13, QFont.Medium, MUTED)


class CalibrationSession:
    """Drives setup across screens and returns {screen id: ScreenProfile} through `on_finish` (None if cancelled)."""

    def __init__(self, screens: list[Screen], every: list[Screen], known: dict[str, ScreenProfile],
                 qt_screen_of: Callable[[Screen], object], on_finish: Callable[[Optional[dict]], None]):
        self.screens, self.every, self.known = screens, every, known
        self.qt_screen_of, self.on_finish = qt_screen_of, on_finish
        self.overlay = Overlay(self._key)
        self.index = 0
        self.results: dict[str, ScreenProfile] = {}
        self.active = True
        self._reset_screen()

    def _reset_screen(self) -> None:
        self.spots: list[tuple[float, float]] = []
        self.spot_index = 0
        self.eyes_only = False
        self.samples: list[tuple[HeadPose, tuple[float, float]]] = []
        self.eye_samples: list[tuple[HeadPose, tuple[float, float]]] = []
        self.count = self.no_face = self.too_small = 0
        self.started = time.monotonic()

    def start(self) -> None:
        self._present()

    def _present(self) -> None:
        s = self.screens[self.index]
        self._reset_screen()
        self.spots = spots_for(s, self.every)
        o = self.overlay
        o.phase = "ready"
        o.progress = 0
        o.screen_label = f"Screen {self.index + 1} of {len(self.screens)}: {s.name}" if len(self.screens) > 1 else s.name
        o.title = "Follow the dot as you naturally would"
        o.subtitle = f"{len(self.spots) + len(EYE_SPOTS)} spots on this screen, about 20 seconds."
        o.shown_spot = QPointF(0.5, 0.5)
        qs = self.qt_screen_of(s)
        if qs is not None:
            o.setScreen(qs)
            o.setGeometry(qs.geometry())
        o.showFullScreen()
        o.raise_()
        o.activateWindow()
        o.setFocus()
        o.update()

    def _key(self, key: int) -> None:
        if key in (Qt.Key_Space, Qt.Key_Return, Qt.Key_Enter) and self.overlay.phase != "running":
            self._show_spot(0)
        elif key == Qt.Key_Escape:
            self.close()
            self.on_finish(None)

    def _show_spot(self, i: int) -> None:
        self.spot_index = i
        self.count = self.no_face = self.too_small = 0
        self.started = time.monotonic()
        o = self.overlay
        o.phase = "running"
        if self.eyes_only:
            o.title = "Now hold your head still"
            o.subtitle = f"Track the dot with your eyes alone. {i + 1} of {len(EYE_SPOTS)}"
            o.move_spot(EYE_SPOTS[i])
        else:
            o.title = "Keep watching the dot"
            o.subtitle = f"Spot {i + 1} of {len(self.spots)}"
            o.move_spot(self.spots[i])

    def add(self, pose: Optional[HeadPose], too_small: bool) -> None:
        """Feed every camera reading here while the session is active."""
        o = self.overlay
        if o.phase != "running":
            return
        t = time.monotonic() - self.started
        duration = 2.0 if self.eyes_only else 1.5
        total = len(self.spots) + len(EYE_SPOTS)
        o.spot_progress = min(t / duration, 1)
        o.progress = (self.spot_index + (len(self.spots) if self.eyes_only else 0) + o.spot_progress) / total
        o.update()
        if t >= (1.0 if self.eyes_only else 0.6):
            if pose:
                (self.eye_samples if self.eyes_only else self.samples).append((pose, o.spot))
                self.count += 1
            elif too_small:
                self.too_small += 1
            else:
                self.no_face += 1
        if t < duration:
            return
        if self.count <= 4:
            self._fail(("You are too far from the camera",
                        "Move closer, or choose another camera in Preferences. Press Space to retry this screen.")
                       if self.too_small > self.no_face else
                       ("No face in view",
                        "Check the light, that nothing covers the camera, and that Preferences uses the camera in front of you. Press Space to retry this screen."))
            return
        nxt = self.spot_index + 1
        if self.eyes_only:
            self._show_spot(nxt) if nxt < len(EYE_SPOTS) else self._complete_screen()
        elif nxt < len(self.spots):
            self._show_spot(nxt)
        else:
            self.eyes_only = True
            self._show_spot(0)

    def _fail(self, message: tuple[str, str]) -> None:
        o = self.overlay
        o.phase = "failed"
        o.title, o.subtitle = message
        self.samples, self.eye_samples, self.eyes_only = [], [], False
        o.update()

    def _complete_screen(self) -> None:
        s = self.screens[self.index]
        kept: list[LookSample] = []
        anchors: list[HeadAngle] = []
        for spot in self.spots:
            group = trimmed([x for x in self.samples if x[1] == spot], lambda x: x[0].yaw, lambda x: x[0].pitch)
            if not group:
                continue
            kept += [LookSample(p, spot[0], spot[1]) for p, _ in group]
            anchors.append(HeadAngle(true_median([p.yaw for p, _ in group]), true_median([p.pitch for p, _ in group])))
        for spot in EYE_SPOTS:
            group = trimmed([x for x in self.eye_samples if x[1] == spot], lambda x: x[0].yaw, lambda x: x[0].pitch)
            kept += [LookSample(p, spot[0], spot[1], eyes_only_phase=True) for p, _ in group]
        self.results[s.id] = ScreenProfile.build(anchors, kept, s.frame)
        self.index += 1
        if self.index < len(self.screens):
            self._present()
            return
        # Two screens whose anchors overlap cannot be told apart.
        merged = {k: v for k, v in self.known.items() if any(x.id == k for x in self.every)}
        merged.update(self.results)
        mids = [HeadAngle(sum(a.yaw for a in p.anchors) / max(len(p.anchors), 1),
                          sum(a.pitch for a in p.anchors) / max(len(p.anchors), 1)) for p in merged.values()]
        gap = min((a.distance(b) for i, a in enumerate(mids) for b in mids[i + 1:]), default=math.inf)
        if len(mids) >= 2 and gap < 4:
            self.index, self.results = 0, {}
            self._present()
            self._fail(("The camera could not tell these screens apart",
                        "Turn your head, not only your eyes, toward each screen. Press Space to start over."))
            return
        self.close()
        self.on_finish(self.results)

    def close(self) -> None:
        self.active = False
        self.overlay.hide()
        self.overlay.deleteLater()
