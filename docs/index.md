---
hide:
  - navigation
---

<div class="hero" markdown>
![Sightline: type where you look](assets/banner.png)
</div>

# Sightline

**Sightline moves keyboard focus to the screen you look at.** Turn toward a monitor and start typing. The webcam notices, and your keystrokes land there. It is free and open source, for macOS and Windows.

## Install

=== "macOS 14 or later"

    ```sh
    curl -fsSL https://raw.githubusercontent.com/abhayymishraa/sightline/main/install.sh | bash
    ```

=== "Windows 10 or 11"

    Run this in PowerShell. You do not need administrator rights.

    ```powershell
    irm https://raw.githubusercontent.com/abhayymishraa/sightline/main/install.ps1 | iex
    ```

The same command updates an existing install. On first launch, **Getting Started** asks for camera access, then has you look at a few dots on each screen, about 30 seconds per screen. Manual downloads are on the [releases page](https://github.com/abhayymishraa/sightline/releases/latest).

## What it does

- **No click before typing.** Turn your head; focus is already there.
- **Windows and panes too.** Inside the screen you face, focus follows the window you look at. On macOS it also follows split panes in terminals and editors.
- **Stays out of your way.** Focus holds while you type and while you use the mouse. A shortcut pauses it.
- **Learns as you work.** Every click tells Sightline where you were looking, so accuracy improves on its own.
- **Private.** Frames are processed in memory, on your machine. Nothing is stored or sent.

<div class="grid" markdown>

![Getting Started on macOS](assets/macos-welcome-light.png#only-light)
![Getting Started on macOS](assets/macos-welcome-dark.png#only-dark)

![Preferences with the live screen map](assets/macos-preferences-light.png#only-light)
![Preferences with the live screen map](assets/macos-preferences-dark.png#only-dark)

</div>

## Next steps

- [User guide](guide.md): first launch, everyday use, and every setting.
- [Troubleshooting](troubleshooting.md): permissions, cameras, and focus problems.
- [How it works](how-it-works.md): the tracking, the gaze model, and how a screen is chosen.
- [Building from source](building.md): build both apps, run the checks, and make a release.
