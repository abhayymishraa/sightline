"""Entry point. `python -m sightline` runs the app; `--selfcheck REPORT` checks the build and exits."""
import sys


def selfcheck(report_path: str) -> int:
    """Used by CI on the packaged .exe: imports every module, finds the model, runs the gaze tests.

    A windowed (no console) build has no sys.stdout or sys.stderr, and an unhandled error opens a dialog
    that waits for a click. So everything is caught and written to `report_path` instead.
    """
    import io
    import traceback
    import unittest

    out = io.StringIO()
    code = 1
    try:
        from . import app, calibration, tracker  # noqa: F401  (import check)
        from . import selftest
        from .paths import asset

        assert tracker.model_path().exists(), "face model missing"
        assert asset("icon.png").exists(), "icon missing"
        suite = unittest.defaultTestLoader.loadTestsFromModule(selftest)
        result = unittest.TextTestRunner(stream=out, verbosity=2).run(suite)
        code = 0 if result.wasSuccessful() else 1
    except BaseException:  # noqa: B036  (report every failure, then exit)
        out.write(traceback.format_exc())
    with open(report_path, "w", encoding="utf-8") as f:
        f.write(out.getvalue())
    return code


def main() -> int:
    if "--selfcheck" in sys.argv:
        i = sys.argv.index("--selfcheck")
        return selfcheck(sys.argv[i + 1] if i + 1 < len(sys.argv) else "selfcheck.txt")

    from PySide6.QtWidgets import QApplication

    from .app import Controller

    app = QApplication(sys.argv)
    app.setApplicationName("Sightline")
    app.setQuitOnLastWindowClosed(False)
    controller = Controller(app)  # noqa: F841  (kept alive for the event loop)
    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
