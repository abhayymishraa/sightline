"""Renders the Windows app's windows to PNG (light and dark) with sample data, for design review.

    python tools/snapshot.py OUT_DIR
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from PySide6.QtCore import QObject, Qt, Signal  # noqa: E402
from PySide6.QtGui import QGuiApplication  # noqa: E402
from PySide6.QtWidgets import QApplication  # noqa: E402

app = QApplication([])

from sightline import ui  # noqa: E402
from sightline.calibration import Overlay  # noqa: E402
from sightline.focus import Screen  # noqa: E402
from sightline.gaze import HeadPose  # noqa: E402
from sightline.prefs import Preferences  # noqa: E402


class SampleController(QObject):
    cameras_found = Signal(list)

    def __init__(self):
        super().__init__()
        self.prefs = Preferences()
        self.state = ui.LiveState()
        self.camera_list = [0, 1]
        self.state.screens = [Screen("a", "DELL S2725HSM", (0, 0, 1920, 1080), "a"),
                              Screen("b", "Built-in Display", (1920, 180, 1512, 982), "b")]
        self.state.profiled = {"a", "b"}
        self.state.looking_at = "a"
        self.state.gaze = (700, 500)
        self.state.pose = HeadPose(12.3, -4.1, 0.4)
        self.state.summary = "Watching, you face DELL S2725HSM"

    def calibrate_all(self): ...
    def calibrate_new(self): ...
    def autostart(self): return False
    def set_autostart(self, on): ...
    def choose_camera(self, i): ...


out = Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)
for scheme, name in ((Qt.ColorScheme.Light, "light"), (Qt.ColorScheme.Dark, "dark")):
    QGuiApplication.styleHints().setColorScheme(scheme)
    app.setStyleSheet(ui.stylesheet())
    ctl = SampleController()
    prefs = ui.PreferencesWindow(ctl)
    prefs.resize(560, 1250)
    prefs.grab().save(str(out / f"preferences-{name}.png"))
    welcome = ui.WelcomeWindow(ctl)
    for i in range(len(welcome.STEPS)):
        welcome.step = i
        welcome.go(0)
        welcome.grab().save(str(out / f"welcome-{i}-{name}.png"))

overlay = Overlay(lambda _: None)
overlay.resize(1280, 800)
overlay.phase, overlay.title, overlay.subtitle = "running", "Keep watching the dot", "Spot 2 of 4"
overlay.shown_spot.setX(0.97)
overlay.spot_progress, overlay.progress = 0.6, 0.3
overlay.grab().save(str(out / "setup.png"))
print(f"Wrote {out}")
