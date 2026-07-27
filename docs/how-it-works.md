# How it works & caveats

## The pipeline

1. **Capture** — ScreenCaptureKit streams just the selected region (cursor
   included). Outcut Share's own overlay windows are excluded from the
   capture, so the dimming and border never reach viewers.
2. **Output** — depending on the *Share as* setting:
   - **Hidden Window** (intended mode): an invisible window — named
     "Outcut Share (Share Region)" by default, renamable in Settings —
     mirrors the region for *window* sharing. macOS stops rendering fully
     offscreen windows, so it keeps exactly one pixel on the bottom-right
     screen corner — effectively invisible, never floating.
   - **Virtual Display** (fallback): a virtual monitor is created via the
     private CoreGraphics `CGVirtualDisplay` API (the same mechanism
     BetterDisplay and DeskPad use), sized 1:1 to the region. Sharing apps
     list it as a normal desktop/screen.
   - **Virtual Monitor:** a standalone empty virtual screen — nothing is
     mirrored onto it; you place windows there and sharing apps capture the
     display directly. The app's capture only feeds the preview panel and
     recordings.
3. **Local feedback** — for region modes, a click-through overlay dims
   everything outside the region and draws the configurable border; the
   Virtual Monitor instead opens a large preview panel that doubles as its
   window manager (drag in/out, layout grid, control mode).

Because the app owns this pipeline, extras happen *inside* it: live
move/resize re-points the running stream (no interruption), pause swaps the
output for a frozen frame or blurred privacy screen, cursor halo/ripples are
drawn into the output only, and recording taps the same frames into an .mp4.

## Caveats

- **Private API:** `CGVirtualDisplay` is not a public API. A future macOS
  could change it — the app then fails with a clear error (and the Hidden
  Window mode keeps working). Not sandboxable / no App Store.
- **Mouse can enter a virtual display** off the screen edge. The app
  arranges its displays **opposite your Dock automatically** (a left/right
  Dock would otherwise migrate onto the virtual screen), so the Dock always
  stays on your real monitor. In Virtual Monitor mode entering is even
  useful — you can arrange windows there directly, and in control mode the
  cursor comes home by pushing any edge of the virtual screen. For region
  sharing, Hidden Window mode avoids the extra display entirely.
- **Crisp text:** with *Crisp text (Retina output)* enabled, virtual
  displays (including the Virtual Monitor) get 2× backing. Meeting apps
  then capture and encode at double resolution — genuinely sharper when the
  source is Retina, and gentler compression on text edges even when it
  isn't.
- **Aspect-locked resize in Virtual Display mode:** the display keeps its
  resolution and content scales into it. Growing the region a lot trades
  sharpness; reselect to recreate the display at full size.
- **Permissions:** Screen Recording is required; a guided window with live
  checkmarks appears when it's missing (menu → *Permissions…*). Accessibility
  is optional — only the Virtual Monitor's window drag & drop and control
  mode use it. Grants stick across rebuilds because builds are signed with a
  stable identity — ad-hoc-signed builds would re-ask every time.
- **Release builds aren't notarized:** right-click → Open once, or
  `xattr -d com.apple.quarantine "Outcut Share.app"`.
- **One session at a time.** Sharing a preset, a new selection or starting
  the Virtual Monitor replaces the active session. When a Virtual Monitor
  session ends, its windows return to your real screen — onto the Space
  you're currently on.
