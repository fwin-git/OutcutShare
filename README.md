# Outcut Share

Share **any part of your screen as its own monitor** in Zoom, Teams, Meet —
drag a rectangle and it appears as a virtual display (or an invisible
shareable window). Made for ultrawides: present one clean slice instead of
the whole desert, without being locked to a single app window.

## Install

Download the latest zip from
[Releases](https://github.com/fwin-git/OutcutShare/releases), unzip, move the
app anywhere. Not notarized: right-click → Open once (or
`xattr -d com.apple.quarantine`). Requires macOS 14+.

## Quick start

1. Menu bar → **Select Region & Share** (⌃⌥⌘S), drag a rectangle — or press
   **Space** and click a window.
2. In your meeting app, share the **"Outcut Share"** screen (or window,
   depending on the mode).
3. Done. **⌃⌥⌘L** re-shares the last region next time; **⌃⌥⌘X** stops.

The first launch guides you through the one required permission
(Screen & System Audio Recording) with live checkmarks.

## What it can do

- **Two share modes** — virtual display ("share screen") or hidden window
  ("share window"), switchable in Settings. → [how it works](docs/how-it-works.md)
- **Live move & resize** while sharing — viewers see the content follow, the
  share never interrupts. Corners + edges, snapping, aspect lock, standard
  sizes. → [modifiers](docs/resize-modifiers.md)
- **Dimming & border** — everything outside the region dims locally, with a
  configurable border; viewers never see either. → [settings](docs/settings.md)
- **Presets & last region** — save regions, re-share with ⌃⌥⌘1–9 or ⌃⌥⌘L.
- **Follow mode** — the region tracks your active window or cursor
  (snap or glide).
- **Privacy pause** (⌃⌥⌘P) — viewers see a frozen frame or a blurred
  privacy screen while you handle something private.
- **Viewer privacy filters** — notification banners and windows of chosen
  apps (Mail, Messages, …) are removed from the shared picture while staying
  visible to you. → [settings](docs/settings.md)
- **Cursor emphasis** — halo + click ripples, drawn for viewers only.
- **Recording** (⌃⌥⌘R) — the region straight to .mp4, no meeting needed.
- **Hotbar** — floating quick actions next to the region (stop, pause,
  record, highlights, resize, preset, follow); draggable, dismissible,
  toggleable from menu & Settings.
- **Global hotkeys** — all rebindable to any combo, with duplicate warnings.
  → [hotkeys](docs/hotkeys.md)

## Docs

| Page | Contents |
| --- | --- |
| [Hotkeys](docs/hotkeys.md) | Defaults, recording combos, duplicate handling |
| [Selection & resize modifiers](docs/resize-modifiers.md) | Space/⇧/⌃ in both overlays, edge handles |
| [How it works & caveats](docs/how-it-works.md) | Virtual display, hidden window, capture pipeline, limitations |
| [Settings reference](docs/settings.md) | Every option on all four pages |
| [Development](docs/development.md) | Build, debug flags, cutting releases |
