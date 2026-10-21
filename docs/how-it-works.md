# How it works

Both apps share one design. The macOS app is Swift (`macos/Sources`); the Windows app is Python (`windows/sightline`). The gaze math is the same on both and is checked by the same test cases (`swift run selfcheck` and `python -m unittest sightline.selftest`).

## Pipeline

```
camera ─▶ face tracker ─▶ head pose ─▶ screen picker ─▶ focus mover
 15 fps    Vision /        yaw, pitch,   which screen?    raise window,
           MediaPipe       pupils, face  (with delay and   move pointer
                           size          hysteresis)
                                  └────▶ gaze regressor ─▶ which window or pane?
```

| Stage | macOS | Windows | What it does |
|---|---|---|---|
| Camera | `FaceTracker.swift` | `tracker.py` | 720p capture, processed at 15 fps. |
| Head pose | Vision face rectangles (yaw, pitch) and landmarks (pupils) | MediaPipe Face Landmarker (rotation matrix and iris points) | Angles in degrees; face size and position as fractions of the frame. |
| Pupils | `pupilOffset` | `_pupil_offset` | Iris centre inside each eye opening, in eye widths, weighted by eye width². Blinks are dropped (openness under 0.6× the median), a 3-frame median removes jitter, and the last value is held for 1.2 s. |
| Smoothing | `OneEuroFilter` | `OneEuroFilter` | 1€ filters: head 0.25 / 0.03, pupils 1 / 0.8, face box 0.5 / 1, gaze point 0.6 / 0.004 (min cutoff / beta). |
| Distance | `HeadPose.scaled` | `HeadPose.scaled` | `atan(k·tan θ)` with `k = base face size / face size`, so sitting closer or farther does not move the boundaries. |
| Setup | `CalibrationSession.swift` | `calibration.py` | Spots along edges shared with neighbouring screens, plus the centre (corners for a lone screen); then four eyes-only spots. 1.5 s per spot with sampling after 0.6 s (eyes-only: 2 s and 1 s). Outliers past 3 MAD are dropped. Screens closer than 4° apart are rejected. |
| Gaze point | `ScreenProfile` | `ScreenProfile` | Ridge regression (λ = 0.02, centred inputs, unpenalised intercept) from 5 head features and 2 pupil features to a point on the screen. A leave-one-spot-out test decides whether pupils help. |
| Screen choice | `ScreenPicker` | `ScreenPicker` | See below. |
| Focus | `FocusMover.swift` (Accessibility API) | `focus.py` (Win32) | Raises the window under the gaze, else the last window used on that screen, else the front window. Moves the pointer only if it is on another screen. |

## Picking a screen

Each screen is a set of anchor head angles from setup. For every frame:

1. Find the nearest anchor of the current screen and of each other screen.
2. Project the head angle onto the line between them: 0 is the current screen, 1 is the other one.
3. The other screen becomes a contender once the projection passes the boundary (**Turn amount**, 50% by default). Screens above or below need 15% more and 0.3 s more, because pitch is noisier than yaw.
4. A contender wins after the switch delay. Each screen keeps focus for at least 0.4 s.
5. Turning back to the previous screen must go 12% (20% vertical) further back than the point where the switch happened. This hysteresis stops flicker at the edge.
6. When the pupil models agree that you look at the other screen, they move the boundary by 25% in that direction.
7. Head angles far from every anchor (looking at the desk or a phone) change nothing.

## Learning from clicks

You look where you click. On each click:

- The difference between the measured and the expected head angle for that spot becomes a **seat shift** sample (up to 30). A regularised linear trend against face position predicts the shift. With few samples it shrinks toward zero.
- If the gaze estimate was near the click (within 45% of the screen), the click joins the regression as a new sample (up to 200).
- A click far from the estimate counts as a miss. When half of the last 8 clicks on a screen miss (4 after the screens moved), Sightline suggests redoing setup.

## Restraint

- Focus holds for 2 s after a keystroke and 1.5 s after mouse use, so reading another window never steals typing.
- Within one screen, only side-by-side windows switch: a window that overlaps the focused one by more than 10% never comes forward.
- On macOS, split panes in known terminals and editors receive `AXFocused`; an optional centre click is a fallback, and only in those apps.
