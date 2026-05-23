# MacTaskbar

Windows-style always-visible taskbar for macOS. Bottom-of-screen bar with a
Start-menu launcher and one tile per open window across all apps.

Free alternative to uBar.

## Build & run

```bash
./build-app.sh
open build/MacTaskbar.app
```

First launch prompts for Accessibility permission. Grant it in
System Settings → Privacy & Security → Accessibility, then quit and
relaunch the app. A yellow "Grant Accessibility" pill appears in the
bar until permission is granted (clicking it deeplinks to the right pane).

## What works (v1)

- Menu-bar agent (`LSUIElement`) — no Dock icon.
- Borderless `NSPanel` pinned to bottom of primary screen at
  `.statusBar` level, joins all Spaces, survives sleep/wake.
- Live window list from `CGWindowListCopyWindowInfo`, refreshed every
  1s plus on `NSWorkspace` launch/terminate/activate notifications.
- Clicking a tile activates the owning app, unminimizes the window,
  and `AXRaise`s it (matched by title).
- Start button opens an app-grid popover scanned from `/Applications`,
  `/System/Applications`, `/System/Applications/Utilities`, and
  `~/Applications`, with a fuzzy-search field.
- Per-tile app icon via `NSRunningApplication.icon`.
- Clock on the right.

## Not yet (per task spec v2)

- Window thumbnails (ScreenCaptureKit).
- Right-click → close/minimize/quit.
- Multi-display.
- Recently-used app row.
- Reserving screen space (currently overlaps the bottom ~56pt).
- AX observers for instant updates — currently polling at 1Hz which
  meets the "~1s update" acceptance criterion.

## Layout

- `main.swift` — NSApplication bootstrap, `.accessory` policy.
- `AppDelegate.swift` — wires panel, workspace observers, 1s timer.
- `TaskbarPanel.swift` — borderless non-activating `NSPanel`.
- `TaskbarView.swift` — SwiftUI bar: Start button, tile strip, clock.
- `WindowEnumerator.swift` — `CGWindowList...` → `[WindowEntry]`.
- `AXBridge.swift` — permission check + raise-by-title.
- `StartMenu.swift` — popover panel with app grid + search.
- `TaskbarModel.swift` — `ObservableObject` driving the bar.
