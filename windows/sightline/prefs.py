"""User preferences in a JSON file. Screen profiles are kept per camera."""
from __future__ import annotations

import json
from dataclasses import asdict, dataclass, field, fields
from typing import Optional

from PySide6.QtCore import QObject, Signal

from .gaze import ScreenProfile
from .paths import data_dir


@dataclass
class Values:
    active: bool = True
    switch_delay_ms: float = 300
    boundary: float = 0.5
    follow_within_screen: bool = True
    window_delay_ms: float = 200
    hold_while_typing: bool = True
    typing_hold_seconds: float = 2.0
    learn_from_clicks: bool = True
    show_gaze_marker: bool = False
    camera_index: Optional[int] = None
    shortcut: str = "Ctrl+Alt+G"
    welcome_finished: bool = False
    profiles: dict = field(default_factory=dict)  # {camera: {screen id: profile json}}


class Preferences(QObject):
    changed = Signal()

    def __init__(self):
        super().__init__()
        self._file = data_dir() / "preferences.json"
        self.v = Values()
        try:
            raw = json.loads(self._file.read_text())
            known = {f.name for f in fields(Values)}
            self.v = Values(**{k: val for k, val in raw.items() if k in known})
        except (OSError, ValueError, TypeError):
            pass
        self._cache: dict[str, dict[str, ScreenProfile]] = {}

    def set(self, **changes) -> None:
        for k, val in changes.items():
            setattr(self.v, k, val)
        self.save()
        self.changed.emit()

    def save(self) -> None:
        tmp = self._file.with_suffix(".tmp")
        tmp.write_text(json.dumps(asdict(self.v)))
        tmp.replace(self._file)

    @property
    def camera_key(self) -> str:
        return str(self.v.camera_index or 0)

    def profiles(self) -> dict[str, ScreenProfile]:
        """Profiles for the camera in use; parsed once and cached."""
        key = self.camera_key
        if key not in self._cache:
            stored = self.v.profiles.get(key, {})
            self._cache[key] = {sid: ScreenProfile.from_json(p) for sid, p in stored.items()}
        return self._cache[key]

    def store_profiles(self, profiles: dict[str, ScreenProfile]) -> None:
        self._cache[self.camera_key] = profiles
        self.v.profiles[self.camera_key] = {sid: p.to_json() for sid, p in profiles.items()}
        self.save()
        self.changed.emit()
