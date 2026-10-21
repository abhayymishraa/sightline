"""Camera → MediaPipe Face Landmarker → filtered HeadPose, 15 times a second, on a worker thread."""
from __future__ import annotations

import math
import sys
import threading
import time
import urllib.request
from pathlib import Path
from typing import Callable, Optional

import cv2
import mediapipe as mp
import numpy as np
from mediapipe.tasks.python import BaseOptions, vision

from .gaze import HeadPose, OneEuroFilter
from .paths import data_dir

MODEL_URL = "https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task"

# Landmark indices of the 478-point face mesh. Corners run image-left → image-right for both eyes.
EYES = (
    {"corners": (33, 133), "lids": (159, 145), "iris": 468},
    {"corners": (362, 263), "lids": (386, 374), "iris": 473},
)


def model_path() -> Path:
    """The bundled model in a packaged build; otherwise downloaded once into the data folder."""
    bundled = Path(getattr(sys, "_MEIPASS", Path(__file__).parent)) / "face_landmarker.task"
    if bundled.exists():
        return bundled
    target = data_dir() / "face_landmarker.task"
    if not target.exists():
        tmp = target.with_suffix(".part")
        urllib.request.urlretrieve(MODEL_URL, tmp)
        tmp.replace(target)
    return target


def list_cameras(limit: int = 5) -> list[int]:
    """Indices of cameras that open. Slow (each probe opens a device), so call it off the UI thread."""
    found = []
    for i in range(limit):
        cap = cv2.VideoCapture(i, cv2.CAP_DSHOW) if sys.platform == "win32" else cv2.VideoCapture(i)
        if cap.isOpened():
            found.append(i)
        cap.release()
    return found


class FaceTracker:
    FPS = 15.0
    SMALLEST_FACE = 0.08
    PUPIL_HOLD_SECONDS = 1.2

    def __init__(self, on_frame: Callable[[Optional[HeadPose], bool], None], on_problem: Callable[[Optional[str]], None]):
        """`on_frame(pose, too_small)` and `on_problem(message or None)` are called on the worker thread."""
        self.on_frame, self.on_problem = on_frame, on_problem
        self._thread: Optional[threading.Thread] = None
        self._stop = threading.Event()
        self.camera_index: Optional[int] = None
        self._reset_filters()

    def _reset_filters(self) -> None:
        self.yaw_f, self.pitch_f = OneEuroFilter(0.25, 0.03), OneEuroFilter(0.25, 0.03)
        self.pupil_x_f, self.pupil_y_f = OneEuroFilter(1, 0.8), OneEuroFilter(1, 0.8)
        self.size_f, self.mid_x_f, self.mid_y_f = OneEuroFilter(0.5, 1), OneEuroFilter(0.5, 1), OneEuroFilter(0.5, 1)
        self._last_pupils: Optional[tuple[float, float, float]] = None
        self._recent_pupils: list[tuple[float, float]] = []
        self._recent_openness: list[float] = []

    @property
    def running(self) -> bool:
        return self._thread is not None and self._thread.is_alive()

    def start(self, camera_index: Optional[int]) -> None:
        self.stop()
        self.camera_index = camera_index if camera_index is not None else 0
        self._stop.clear()
        self._thread = threading.Thread(target=self._run, name="sightline-camera", daemon=True)
        self._thread.start()

    def stop(self) -> None:
        if self._thread:
            self._stop.set()
            self._thread.join(timeout=3)
            self._thread = None

    def _run(self) -> None:
        try:
            options = vision.FaceLandmarkerOptions(
                base_options=BaseOptions(model_asset_path=str(model_path())),
                running_mode=vision.RunningMode.VIDEO,
                num_faces=1,
                output_facial_transformation_matrixes=True,
            )
            landmarker = vision.FaceLandmarker.create_from_options(options)
        except Exception as error:  # model download or load failed
            self.on_problem(f"Could not load the face model: {error}")
            return

        backend = cv2.CAP_DSHOW if sys.platform == "win32" else cv2.CAP_ANY
        cap = cv2.VideoCapture(self.camera_index, backend)
        if not cap.isOpened():
            self.on_problem("Windows blocked the camera, or another app is using it")
            landmarker.close()
            return
        cap.set(cv2.CAP_PROP_FRAME_WIDTH, 1280)
        cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 720)
        self._reset_filters()

        started = last_frame = time.monotonic()
        next_due = 0.0
        reported_ok = False
        try:
            while not self._stop.is_set():
                ok, frame = cap.read()
                now = time.monotonic()
                if not ok:
                    if now - last_frame > 4:
                        self.on_problem("The camera sends no frames")
                    time.sleep(0.05)
                    continue
                last_frame = now
                if not reported_ok:
                    self.on_problem(None)
                    reported_ok = True
                if now < next_due - 0.012:
                    continue
                next_due = max(next_due, now - 1 / self.FPS) + 1 / self.FPS
                rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                result = landmarker.detect_for_video(mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb),
                                                     int((now - started) * 1000))
                self._handle(result, frame.shape[1], frame.shape[0], now)
        finally:
            cap.release()
            landmarker.close()

    def _handle(self, result, width: int, height: int, now: float) -> None:
        if not result.face_landmarks or not result.facial_transformation_matrixes:
            self._reset_filters()
            self.on_frame(None, False)
            return
        lm = result.face_landmarks[0]
        xs = [p.x for p in lm]
        ys = [p.y for p in lm]
        if max(xs) - min(xs) < self.SMALLEST_FACE:
            self._reset_filters()
            self.on_frame(None, True)
            return

        r = np.asarray(result.facial_transformation_matrixes[0])[:3, :3]
        yaw = math.degrees(math.atan2(r[0, 2], r[2, 2]))
        pitch = math.degrees(math.asin(max(-1.0, min(1.0, -r[1, 2]))))

        pose = HeadPose(
            yaw=self.yaw_f(yaw, now),
            pitch=self.pitch_f(pitch, now),
            face_size=self.size_f(max(ys) - min(ys), now),
            face_mid_x=self.mid_x_f(sum(xs) / len(xs), now),
            face_mid_y=self.mid_y_f(sum(ys) / len(ys), now),
        )
        pupils = self._steady(self._pupil_offset(lm, width, height))
        if pupils:
            pose.pupil_x = self.pupil_x_f(pupils[0], now)
            pose.pupil_y = self.pupil_y_f(pupils[1], now)
            self._last_pupils = (pose.pupil_x, pose.pupil_y, now)
        elif self._last_pupils and now - self._last_pupils[2] < self.PUPIL_HOLD_SECONDS:
            pose.pupil_x, pose.pupil_y = self._last_pupils[0], self._last_pupils[1]
        else:
            self._last_pupils = None
            self._recent_pupils = []
            self.pupil_x_f.reset()
            self.pupil_y_f.reset()
        self.on_frame(pose, False)

    @staticmethod
    def _pupil_offset(lm, width: int, height: int) -> Optional[tuple[float, float, float]]:
        """Iris centre inside each eye opening, in eye widths, weighted by eye width² (the nearer eye is sharper)."""
        def px(i):
            return np.array([lm[i].x * width, lm[i].y * height])

        sx = sy = so = total = 0.0
        for eye in EYES:
            a, b = px(eye["corners"][0]), px(eye["corners"][1])
            axis = b - a
            w = float(np.hypot(*axis))
            if w < 4:
                continue
            u = axis / w
            d = px(eye["iris"]) - (a + b) / 2
            weight = w * w
            sx += weight * float(d @ u) / w
            sy += weight * float(u[0] * d[1] - u[1] * d[0]) / w
            so += weight * float(np.hypot(*(px(eye["lids"][0]) - px(eye["lids"][1])))) / w
            total += weight
        return (sx / total, sy / total, so / total) if total else None

    def _steady(self, reading: Optional[tuple[float, float, float]]) -> Optional[tuple[float, float]]:
        """Drops blinks (eye much less open than usual), then takes a 3-frame median against jitter."""
        if reading is None:
            return None
        x, y, openness = reading
        usual = sorted(self._recent_openness)[len(self._recent_openness) // 2] if self._recent_openness else 0
        self._recent_openness = (self._recent_openness + [openness])[-150:]
        if len(self._recent_openness) >= 15 and openness < usual * 0.6:
            return None
        self._recent_pupils = (self._recent_pupils + [(x, y)])[-3:]
        mx = sorted(p[0] for p in self._recent_pupils)[len(self._recent_pupils) // 2]
        my = sorted(p[1] for p in self._recent_pupils)[len(self._recent_pupils) // 2]
        return mx, my
