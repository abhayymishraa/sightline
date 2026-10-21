# Contributing

Thanks for helping with Sightline. Bug reports, ideas and pull requests are all welcome.

## Before you open a pull request

1. Keep the two apps in step. A change to the gaze math (`macos/Sources/GazeCore` or `windows/sightline/gaze.py`) belongs in both, with the same test case added to `macos/Sources/selfcheck/main.swift` and `windows/sightline/selftest.py`.
2. Run the checks:

   ```sh
   cd macos && swift run selfcheck
   cd windows && python -m unittest sightline.selftest
   ```

3. For UI changes, attach before and after screenshots in light and dark mode (`Sightline --snapshot DIR` on macOS, `python tools/snapshot.py DIR` for the Windows UI).
4. Use [Conventional Commit](https://www.conventionalcommits.org) messages, for example `fix(windows): keep focus on minimized windows`.

## Good first areas

- Split-pane focus on Windows through UI Automation.
- More terminals and editors in the macOS pane list (`FocusMover.swift`).
- Linux support (X11 or Wayland focus, same gaze core).
- Homebrew cask and winget manifests.

## Reporting a bug

Use the issue template. Include your OS version, camera, screen layout, and what the status line in the menu says. Never attach camera images; Sightline does not need them to debug.
