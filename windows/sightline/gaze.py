"""Gaze math, shared in behaviour with the macOS app's GazeCore.

Pure Python plus numpy: no camera, no UI. `python -m unittest` in windows/ exercises it.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field, asdict
from typing import Callable, Optional

import numpy as np


class OneEuroFilter:
    """The 1€ filter (Casiez et al., CHI 2012): low lag on fast moves, strong smoothing when still."""

    def __init__(self, min_cutoff: float, beta: float, d_cutoff: float = 1.0):
        self.min_cutoff, self.beta, self.d_cutoff = min_cutoff, beta, d_cutoff
        self.value: Optional[float] = None
        self.derivative = 0.0
        self.last_time = 0.0

    def reset(self) -> None:
        self.value = None
        self.derivative = 0.0

    @staticmethod
    def _alpha(cutoff: float, dt: float) -> float:
        return 1.0 / (1.0 + 1.0 / (2 * math.pi * cutoff * dt))

    def __call__(self, x: float, t: float) -> float:
        previous, last = self.value, self.last_time
        self.last_time = t
        if previous is None or t <= last:
            self.value = x
            return x
        dt = t - last
        self.derivative += self._alpha(self.d_cutoff, dt) * ((x - previous) / dt - self.derivative)
        cutoff = self.min_cutoff + self.beta * abs(self.derivative)
        self.value = previous + self._alpha(cutoff, dt) * (x - previous)
        return self.value


@dataclass
class HeadAngle:
    yaw: float
    pitch: float

    def distance(self, o: "HeadAngle") -> float:
        return math.hypot(self.yaw - o.yaw, self.pitch - o.pitch)

    def __sub__(self, o: "HeadAngle") -> "HeadAngle":
        return HeadAngle(self.yaw - o.yaw, self.pitch - o.pitch)

    def __add__(self, o: "HeadAngle") -> "HeadAngle":
        return HeadAngle(self.yaw + o.yaw, self.pitch + o.pitch)

    def dot(self, o: "HeadAngle") -> float:
        return self.yaw * o.yaw + self.pitch * o.pitch


@dataclass
class HeadPose:
    """One camera reading. Angles in degrees; face numbers are fractions of the camera frame."""
    yaw: float
    pitch: float
    face_size: float
    face_mid_x: float = 0.5
    face_mid_y: float = 0.5
    pupil_x: Optional[float] = None
    pupil_y: Optional[float] = None

    def scaled(self, base_face_size: float) -> "HeadPose":
        """The angles as they would read with the face at `base_face_size`."""
        k = base_face_size / max(self.face_size, 0.01)
        return HeadPose(
            math.degrees(math.atan(k * math.tan(math.radians(self.yaw)))),
            math.degrees(math.atan(k * math.tan(math.radians(self.pitch)))),
            self.face_size, self.face_mid_x, self.face_mid_y, self.pupil_x, self.pupil_y,
        )

    def features(self, base_face_size: float, with_pupils: bool) -> Optional[list[float]]:
        k = base_face_size / max(self.face_size, 0.01)
        ty = k * math.tan(math.radians(self.yaw))
        tp = math.tan(math.radians(self.pitch))
        f = [5 * ty, 5 * k * tp, 5 * ty * abs(ty), 5 * k * (self.face_mid_x - 0.5), 5 * k * (self.face_mid_y - 0.5)]
        if with_pupils:
            if self.pupil_x is None or self.pupil_y is None:
                return None
            f += [20 * k * self.pupil_x, 20 * k * self.pupil_y]
        return f

    @property
    def angle(self) -> HeadAngle:
        return HeadAngle(self.yaw, self.pitch)


@dataclass
class LookSample:
    """A pose recorded while the user looked at spot (x, y) of a screen; unit square, y down."""
    pose: HeadPose
    x: float
    y: float
    eyes_only_phase: bool = False

    @property
    def key(self) -> str:
        return f"{self.x},{self.y}"


def middle_value(values: list[float]) -> float:
    return sorted(values)[len(values) // 2] if values else 0.5


@dataclass
class GazeRegressor:
    """Ridge regression to a point. Inputs centred; the intercept is not penalised."""
    centre: list[float]
    weights_x: list[float]
    weights_y: list[float]

    RIDGE = 0.02

    @staticmethod
    def train(inputs: list[list[float]], outputs: list[tuple[float, float]], ridge: float = RIDGE) -> Optional["GazeRegressor"]:
        n = len(inputs)
        if n < 8 or n != len(outputs):
            return None
        x = np.asarray(inputs, dtype=float)
        centre = x.mean(axis=0)
        r = np.hstack([np.ones((n, 1)), x - centre])
        a = r.T @ r
        a[1:, 1:] += np.eye(x.shape[1]) * ridge * n
        y = np.asarray(outputs, dtype=float)
        try:
            w = np.linalg.solve(a, r.T @ y)
        except np.linalg.LinAlgError:
            return None
        return GazeRegressor(centre.tolist(), w[:, 0].tolist(), w[:, 1].tolist())

    def map(self, f: list[float]) -> tuple[float, float]:
        r = np.concatenate([[1.0], np.asarray(f) - np.asarray(self.centre)])
        return float(r @ self.weights_x), float(r @ self.weights_y)


@dataclass
class SeatShift:
    yaw: float
    pitch: float
    face_mid_x: float
    face_mid_y: float


def trimmed(items: list, yaw: Callable, pitch: Callable) -> list:
    """Drops items more than 3 median absolute deviations (at least 1°) from the median."""
    if len(items) < 5:
        return items
    my, mp = middle_value([yaw(i) for i in items]), middle_value([pitch(i) for i in items])
    dy = max(3 * middle_value([abs(yaw(i) - my) for i in items]), 1)
    dp = max(3 * middle_value([abs(pitch(i) - mp) for i in items]), 1)
    kept = [i for i in items if abs(yaw(i) - my) <= dy and abs(pitch(i) - mp) <= dp]
    return items if len(kept) <= 2 else kept


@dataclass
class ScreenProfile:
    """What one screen looks like from the user's seat."""
    base_face_size: float
    middle: HeadAngle
    anchors: list[HeadAngle]
    samples: list[LookSample]
    clicks: list[LookSample] = field(default_factory=list)
    seat_shifts: list[SeatShift] = field(default_factory=list)
    frame: Optional[tuple[float, float, float, float]] = None
    pupils_useful: Optional[bool] = None
    with_pupils: Optional[GazeRegressor] = None
    head_only: Optional[GazeRegressor] = None

    @staticmethod
    def build(anchors: list[HeadAngle], samples: list[LookSample], frame=None) -> "ScreenProfile":
        base = middle_value([s.pose.face_size for s in samples]) if samples else 0.3
        p = ScreenProfile(base, anchors[0] if anchors else HeadAngle(0, 0), anchors, samples, frame=frame)
        p.retrain()
        pupils, head = p.cross_validate(True), p.cross_validate(False)
        if pupils and head:
            p.pupils_useful = pupils[0] < head[0]
        return p

    def retrain(self) -> None:
        everything = self.samples + self.clicks
        rows = [(f, (s.x, s.y)) for s in everything if (f := s.pose.features(self.base_face_size, True))]
        self.with_pupils = GazeRegressor.train([r[0] for r in rows], [r[1] for r in rows])
        head = [s for s in everything if not s.eyes_only_phase]
        self.head_only = GazeRegressor.train([s.pose.features(self.base_face_size, False) for s in head],
                                             [(s.x, s.y) for s in head])

    @property
    def pupil_model(self) -> Optional[GazeRegressor]:
        return None if self.pupils_useful is False else self.with_pupils

    def locate(self, pose: HeadPose) -> Optional[tuple[float, float]]:
        p = None
        f = pose.features(self.base_face_size, True)
        if self.pupils_useful is not False and self.with_pupils and f:
            p = self.with_pupils.map(f)
        elif self.head_only:
            p = self.head_only.map(pose.features(self.base_face_size, False))
        return None if p is None else (min(max(p[0], 0), 1), min(max(p[1], 0), 1))

    def cross_validate(self, with_pupils: bool) -> Optional[tuple[float, float]]:
        """Leave-one-spot-out (error, scatter) in fractions of the screen."""
        pool = self.samples if with_pupils else [s for s in self.samples if not s.eyes_only_phase]
        spots: dict[str, list[LookSample]] = {}
        for s in self.samples:
            if not s.eyes_only_phase:
                spots.setdefault(s.key, []).append(s)
        errors, scatter = [], []
        for key, held in spots.items():
            rows = [(f, (s.x, s.y)) for s in pool if s.key != key and (f := s.pose.features(self.base_face_size, with_pupils))]
            model = GazeRegressor.train([r[0] for r in rows], [r[1] for r in rows])
            if not model:
                continue
            guesses = [model.map(f) for s in held if (f := s.pose.features(self.base_face_size, with_pupils))]
            if not guesses:
                continue
            tx, ty = held[0].x, held[0].y
            errors += [math.hypot(gx - tx, gy - ty) for gx, gy in guesses]
            mx, my = middle_value([g[0] for g in guesses]), middle_value([g[1] for g in guesses])
            scatter += [math.hypot(gx - mx, gy - my) for gx, gy in guesses]
        if not errors:
            return None
        return sum(errors) / len(errors), sum(scatter) / len(scatter)

    def absorb_click(self, pose: HeadPose, spot: tuple[float, float]) -> None:
        """A click at `spot`: the seat shift always learns; the regression learns only from near guesses."""
        scaled = pose.scaled(self.base_face_size)
        expected = self._expected_angle(spot)
        if abs(scaled.yaw - expected.yaw) < 25 and abs(scaled.pitch - expected.pitch) < 20:
            self.seat_shifts.append(SeatShift(scaled.yaw - expected.yaw, scaled.pitch - expected.pitch,
                                              pose.face_mid_x, pose.face_mid_y))
            self.seat_shifts = self.seat_shifts[-30:]
        guess = self.locate(pose)
        if guess is None or math.hypot(guess[0] - spot[0], guess[1] - spot[1]) >= 0.45:
            return
        self.clicks = (self.clicks + [LookSample(pose, spot[0], spot[1])])[-200:]
        self.retrain()

    def shifted_anchors(self, pose: HeadPose) -> list[HeadAngle]:
        s = self.seat_shift(pose)
        return [a + s for a in self.anchors]

    def seat_shift(self, pose: HeadPose) -> HeadAngle:
        s = trimmed(self.seat_shifts, lambda o: o.yaw, lambda o: o.pitch)
        if len(s) < 3:
            return HeadAngle(0, 0)
        x = self._trend([(o.yaw, o.face_mid_x) for o in s], pose.face_mid_x)
        y = self._trend([(o.pitch, o.face_mid_y) for o in s], pose.face_mid_y)
        confidence = len(s) / (len(s) + 4)
        return HeadAngle(confidence * x, confidence * y)

    @staticmethod
    def _trend(pairs: list[tuple[float, float]], face: float) -> float:
        n = len(pairs)
        mean_face = sum(p[1] for p in pairs) / n
        mean_shift = sum(p[0] for p in pairs) / n
        if n < 8:
            return mean_shift
        cov = sum((s - mean_shift) * (f - mean_face) for s, f in pairs)
        spread = sum((f - mean_face) ** 2 for _, f in pairs)
        return mean_shift + (face - mean_face) * cov / (spread + 0.0005 * n)

    def _expected_angle(self, p: tuple[float, float]) -> HeadAngle:
        groups: dict[str, list[LookSample]] = {}
        for s in self.samples:
            if not s.eyes_only_phase:
                groups.setdefault(s.key, []).append(s)
        sw = sy = sp = 0.0
        for group in groups.values():
            tx, ty = group[0].x, group[0].y
            scaled = [s.pose.scaled(self.base_face_size) for s in group]
            w = 1 / ((tx - p[0]) ** 2 + (ty - p[1]) ** 2 + 0.001)
            sw += w
            sy += w * middle_value([s.yaw for s in scaled])
            sp += w * middle_value([s.pitch for s in scaled])
        return HeadAngle(sy / sw, sp / sw) if sw > 0 else self.middle

    # Persistence: models are retrained on load, so only data is stored.
    def to_json(self) -> dict:
        d = asdict(self)
        d.pop("with_pupils"); d.pop("head_only")
        return d

    @staticmethod
    def from_json(d: dict) -> "ScreenProfile":
        def pose(p): return HeadPose(**p)
        def sample(s): return LookSample(pose(s["pose"]), s["x"], s["y"], s["eyes_only_phase"])
        p = ScreenProfile(
            d["base_face_size"], HeadAngle(**d["middle"]), [HeadAngle(**a) for a in d["anchors"]],
            [sample(s) for s in d["samples"]], [sample(s) for s in d["clicks"]],
            [SeatShift(**o) for o in d["seat_shifts"]], tuple(d["frame"]) if d.get("frame") else None,
            d.get("pupils_useful"),
        )
        p.retrain()
        return p


class ScreenPicker:
    """Picks the screen the user faces from head angles; see the macOS ScreenPicker for the full rationale."""
    BACKOFF, VERTICAL_BACKOFF = 0.12, 0.2
    EYE_NUDGE = 0.25
    VERTICAL_BOUNDARY_EXTRA, VERTICAL_DELAY_EXTRA = 0.15, 0.3
    MINIMUM_HOLD = 0.4
    SIDE_TOLERANCE, SIDE_TOLERANCE_FRACTION = 5.0, 0.5

    def __init__(self):
        self.screen: Optional[str] = None
        self.reset()
        self._last_move_at = -math.inf

    def reset(self) -> None:
        self.screen = None
        self._last_screen: Optional[str] = None
        self._pivot: Optional[tuple[HeadAngle, HeadAngle]] = None
        self._crossed_at = 0.0
        self._contender: Optional[str] = None
        self._contender_since = 0.0
        self._contender_seen = 0.0

    def pin(self, screen: str) -> None:
        if screen != self.screen:
            self.screen, self._last_screen, self._pivot, self._contender = screen, None, None, None

    @staticmethod
    def _nearest(p: HeadAngle, anchors: list[HeadAngle]) -> Optional[HeadAngle]:
        return min(anchors, key=p.distance) if anchors else None

    @staticmethod
    def _mean(anchors: list[HeadAngle]) -> HeadAngle:
        n = max(len(anchors), 1)
        return HeadAngle(sum(a.yaw for a in anchors) / n, sum(a.pitch for a in anchors) / n)

    def step(self, head: HeadAngle, anchors: dict[str, list[HeadAngle]], delay: float, boundary: float,
             now: float, pupils: Optional[Callable[[str], Optional[bool]]] = None) -> Optional[str]:
        """Returns the screen to move to now, or None."""
        p = head
        scored = [(sid, p.distance(n)) for sid, lst in anchors.items() if (n := self._nearest(p, lst))]
        if len(anchors) < 2 or not scored:
            self._contender = None
            return None
        near = min(scored, key=lambda t: t[1])
        gap = min((a.distance(b) for i, la in enumerate(anchors.values()) for j, lb in enumerate(anchors.values())
                   if j > i for a in la for b in lb), default=math.inf)
        if near[1] > max(12, 0.8 * gap):
            self._contender = None
            return None
        here = self.screen
        here_anchor = self._nearest(p, anchors.get(here, [])) if here else None
        if here_anchor is None:
            self.screen, self._last_screen, self._pivot, self._contender = near[0], None, None, None
            return None
        here_mid = self._mean(anchors[here])
        d = p - here_anchor

        best = None
        contender_aside = False
        for sid, lst in anchors.items():
            if sid == here or not lst:
                continue
            there = self._nearest(p, lst)
            axis = there - here_anchor
            length = math.sqrt(axis.dot(axis))
            aside = abs(d.yaw * axis.pitch - d.pitch * axis.yaw) / length if length > 1e-9 else math.sqrt(d.dot(d))
            if aside > max(self.SIDE_TOLERANCE, self.SIDE_TOLERANCE_FRACTION * length):
                contender_aside = contender_aside or self._contender == sid
                continue
            t = d.dot(axis) / (length * length) if length > 1e-9 else 0
            vote = pupils(sid) if pupils else None
            nudge = self.EYE_NUDGE if vote is True else -self.EYE_NUDGE if vote is False else 0
            mid = self._mean(lst)
            vertical = abs(mid.yaw - here_mid.yaw) < abs(mid.pitch - here_mid.pitch)
            line = min(boundary + (self.VERTICAL_BOUNDARY_EXTRA if vertical else 0), 0.9) - nudge
            score, passes = t, line <= t
            if sid == self._last_screen and self._pivot:
                a, b = self._pivot
                back = b - a
                l2 = back.dot(back)
                t_back = (p - a).dot(back) / l2 if l2 > 1e-9 else 0
                passes = t_back <= self._crossed_at - (self.VERTICAL_BACKOFF if vertical else self.BACKOFF) + nudge
                score = max(t, 1 - t_back)
            if passes and score > (best[1] if best else 0):
                best = (sid, score, line, vertical, there)

        if best is None:
            if not (contender_aside and now - self._contender_seen <= 0.25):
                self._contender = None
            return None
        sid, _, line, vertical, there = best
        self._contender_seen = now
        if self._contender != sid:
            self._contender, self._contender_since = sid, now
            return None
        if now - self._contender_since < delay + (self.VERTICAL_DELAY_EXTRA if vertical else 0):
            return None
        if now - self._last_move_at < self.MINIMUM_HOLD:
            return None
        previous = here
        self.screen, self._last_move_at, self._contender = sid, now, None
        if self._last_screen == sid:
            self._pivot = self._last_screen = None
            return sid
        to = self._nearest(here_anchor, anchors[sid]) or there
        axis = to - here_anchor
        l2 = axis.dot(axis)
        self._pivot = (here_anchor, to)
        self._crossed_at = min(line, d.dot(axis) / l2) if l2 > 1e-9 else 0
        self._last_screen = previous
        return sid


class MissCounter:
    """Per screen, how often the gaze estimate disagrees with where the user clicks."""

    def __init__(self):
        self._results: dict[str, list[bool]] = {}
        self.suspect: set[str] = set()

    def is_unreliable(self, screen: str) -> bool:
        r = self._results.get(screen, [])
        return len(r) >= (4 if screen in self.suspect else 8) and sum(r) / len(r) >= 0.5

    def note(self, screen: str, miss: bool) -> bool:
        """True only when the screen turns unreliable with this result."""
        was = self.is_unreliable(screen)
        self._results[screen] = (self._results.get(screen, []) + [miss])[-16:]
        return not was and self.is_unreliable(screen)

    def forget(self, screen: str) -> None:
        self._results.pop(screen, None)
