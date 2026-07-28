# Outcut Share

<p align="center">
  <img src="Resources/AppIcon.png" alt="Outcut Share app icon" width="160">
</p>

Share exactly what you mean to share in Zoom, Teams, Meet — nothing else.
Two ways:

- **Region sharing** — drag a rectangle over any part of your screen and it
  becomes an invisible shareable window. Made for ultrawides: present one
  clean slice instead of the whole desert, without being locked to a single
  app window.
- **Virtual Monitor** — a separate, empty screen only you can fill. Drag
  windows onto its preview and *only they* are ever shared; the rest of
  your desktop stays private by construction.

## Feature showcase

**Select a region — freeform, standard sizes (⌃), locked aspect (⇧), move
with Space, or pick a whole window — while the call mirrors it live:**

![Region selection with all modifier modes, mirrored into a mock call](docs/media/demo-region.gif)

**Follow mode — the region tracks your active window, then trails the
cursor:**

![Follow modes tracking the active window and the cursor](docs/media/demo-follow.gif)

**Virtual Monitor — drag windows onto a private screen, lay them out on
the 3 × 3 grid (⇧), pull them back out:**

![Virtual Monitor with drag & drop, layout grid and pull-out](docs/media/demo-monitor.gif)

*(All clips are recorded by the app itself — `--demo=region|follow|monitor`
produces them on a synthetic stage with fake content, see
[development](docs/development.md).)*

## Install

Download the latest zip from
[Releases](https://github.com/fwin-git/OutcutShare/releases), unzip, move the
app anywhere. Not notarized: right-click → Open once (or
`xattr -d com.apple.quarantine`). Requires macOS 14+.

## Quick start — share a region

1. Menu bar → **Select Region & Share** (⌃⌥⌘S), drag a rectangle — or press
   **Space** and click a window.
2. In your meeting app, share the window named **"Outcut Share (Share
   Region)"** (rename it in Settings).
3. Done. **⌃⌥⌘L** re-shares the last region next time; **⌃⌥⌘X** stops.

Region sharing runs as a **hidden window** — the intended mode: it lists
under "share window", resizes live without interrupting the share, and your
cursor can't wander onto it. If your meeting tool can't capture windows,
switch *Settings → Share as* to **Virtual Display** — the same region
appears as an extra monitor under "share screen" instead (fallback; see
[how it works](docs/how-it-works.md) for the trade-offs).

The first launch guides you through the one required permission
(Screen & System Audio Recording) with live checkmarks.

## Quick start — Virtual Monitor

1. *Settings → Share as →* **Virtual Monitor**, then menu bar → **Start
   Virtual Monitor & Share**.
2. A large preview panel opens — your window into the new screen. **Drag
   any window onto it** to move it there; share the monitor under "share
   screen" in your meeting app.
3. Arrange through the preview: drag windows around (a live ghost follows),
   hold **⇧** for a 3 × 3 layout grid — drop in a cell or sweep across
   cells to span rows, columns and blocks. Drag a window off the panel to
   bring it back to your real screen.
4. The cursor button turns on **control mode**: click through the preview
   to drive folders and browsers on the monitor; push any edge of the
   virtual screen to bring the cursor home.

Everything on the monitor comes back to your screen (and your current
Space) when you stop. Window moving uses the optional Accessibility
permission; a guided row appears when it's needed.

## What else it can do

- **Live move & resize** while sharing a region — viewers see the content
  follow, the share never interrupts. Corners + edges, snapping, aspect
  lock, standard sizes. → [modifiers](docs/resize-modifiers.md)
- **Dimming & border** — everything outside the region dims locally, with a
  configurable border; viewers never see either. → [settings](docs/settings.md)
- **Shared-output preview** — a small floating window with exactly what
  viewers see, no need to keep the meeting app open.
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
- **Hotbar** — floating quick actions next to the region or monitor preview
  (stop, pause, record, highlights, preview, resize, preset, follow);
  draggable, dismissible, toggleable from menu & Settings.
- **Global hotkeys** — all rebindable to any combo, with duplicate warnings.
  → [hotkeys](docs/hotkeys.md)
- **Raycast extension** — trigger sharing, presets, pause, recording and
  modes from Raycast (or any tool, via `outcutshare://` deep links).
  → [raycast](docs/raycast.md)

## Docs

| Page | Contents |
| --- | --- |
| [Hotkeys](docs/hotkeys.md) | Defaults, recording combos, duplicate handling |
| [Raycast & URL scheme](docs/raycast.md) | Extension setup, every outcutshare:// command |
| [Selection & resize modifiers](docs/resize-modifiers.md) | Space/⇧/⌃ in both overlays, edge handles |
| [How it works & caveats](docs/how-it-works.md) | Hidden window, virtual displays, capture pipeline, limitations |
| [Settings reference](docs/settings.md) | Every option on all pages, incl. the Virtual Monitor |
| [Development](docs/development.md) | Build, debug flags, cutting releases |
