# User guide

## First launch

The **Getting Started** window walks through five short steps.

1. **Access.** Allow the camera. On macOS, also allow Accessibility (Sightline needs it to raise windows and move the pointer). The page updates by itself when access changes.
2. **Screens.** Press **Start Setup**. Each screen in turn becomes bright and shows a dot.
   - Press <kbd>Space</kbd> and follow the dot the way you normally would, with head and eyes.
   - Then four dots appear for your eyes only. Keep your head still.
   - Press <kbd>Esc</kbd> at any time to cancel.
3. **Tune.** The defaults suit most people.
4. **Test.** Look from screen to screen. The map highlights the screen you face.
5. **Done.** Sightline now runs from the menu bar (macOS) or the notification area (Windows).

> **Tip:** sit the way you usually work during setup, and use the camera that faces you most directly.

## Everyday use

- **Switch screens:** turn your head toward the other screen and keep it there for a moment (300 ms by default).
- **Switch windows on one screen:** look at a window that sits next to the focused one. Overlapping windows never switch, so a window behind another one does not jump forward.
- **Switch panes (macOS):** look at another split pane in a terminal or code editor.
- **Type freely:** while you type, focus holds (2 seconds after the last keystroke by default). After you use the mouse, focus holds for 1.5 seconds.
- **Pause:** press <kbd>Ctrl</kbd> + <kbd>Option</kbd> + <kbd>G</kbd> (macOS) or <kbd>Ctrl</kbd> + <kbd>Alt</kbd> + <kbd>G</kbd> (Windows), or use the menu.

## Preferences

| Setting | What it does | Default |
|---|---|---|
| Switch delay | How long you must face another screen before focus moves. Short is quick; long ignores brief looks. | 300 ms |
| Turn amount | Where the boundary between two screens sits, as a share of the way between their setup spots. Low switches with a small turn. | 50% |
| Follow windows and panes | Also move focus inside the screen you face. | On |
| Pane / window delay | Look time before a window or pane gets focus. | 200 ms |
| Click panes that resist (macOS) | Some terminals ignore focus requests for split panes. Sightline then clicks the pane centre and puts the pointer back. Only in terminals and editors. | On |
| Hold focus while typing | Focus does not move while you type. | On, 2 s |
| Learn from clicks | Each click on the screen you face becomes a reference point. Redoing setup clears what was learned. | On |
| Show gaze marker | A rough dot where Sightline thinks you look. Useful to check the setup. | Off |
| Camera | Which camera to use. Each camera keeps its own setup. | Automatic |
| Pause shortcut | A system-wide shortcut. It must include Ctrl, Option/Alt or Command. | Ctrl Option/Alt G |
| Open at login | Start Sightline when you log in. | Off |

## When to redo setup

Redo setup after you move a monitor, change the screen arrangement in system settings, or switch to a camera in a different place. Sightline warns in its menu when focus often misses on a screen, or when your screens moved.
