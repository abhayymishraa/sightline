import os
import sys
from pathlib import Path


def data_dir() -> Path:
    """%APPDATA%\\Sightline on Windows; ~/Library/Application Support/Sightline when developing on a Mac."""
    if sys.platform == "win32":
        base = Path(os.environ.get("APPDATA", Path.home()))
    else:
        base = Path.home() / "Library" / "Application Support"
    path = base / "Sightline"
    path.mkdir(parents=True, exist_ok=True)
    return path


def asset(name: str) -> Path:
    """A file shipped next to the package (or inside the PyInstaller bundle)."""
    return Path(getattr(sys, "_MEIPASS", Path(__file__).parent)) / "assets" / name
