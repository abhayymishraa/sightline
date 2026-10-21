"""Entry point. `python -m sightline` runs the app; `--selfcheck` checks the build and exits."""
import sys


def selfcheck() -> int:
    """Used by CI on the packaged .exe: imports every module, finds the model, runs the gaze tests."""
    import unittest

    from . import app, calibration, tracker  # noqa: F401  (import check)
    from .paths import asset

    assert tracker.model_path().exists(), "face model missing"
    assert asset("icon.png").exists(), "icon missing"
    from . import selftest
    result = unittest.TextTestRunner(verbosity=1).run(unittest.defaultTestLoader.loadTestsFromModule(selftest))
    return 0 if result.wasSuccessful() else 1


def main() -> int:
    if "--selfcheck" in sys.argv:
        return selfcheck()

    from PySide6.QtWidgets import QApplication

    from .app import Controller

    app = QApplication(sys.argv)
    app.setApplicationName("Sightline")
    app.setQuitOnLastWindowClosed(False)
    controller = Controller(app)  # noqa: F841  (kept alive for the event loop)
    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
