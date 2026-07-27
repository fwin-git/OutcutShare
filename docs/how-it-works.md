# How it works & caveats

## The pipeline

1. **Capture** — ScreenCaptureKit streams just the selected region (cursor
   included). Outcut Share's own overlay windows are excluded from the
   capture, so the dimming and border never reach viewers.
2. **Output** — depending on the *Share as* setting:
   - **Virtual Display:** a virtual monitor is created via the private
     CoreGraphics `CGVirtualDisplay` API (the same mechanism BetterDisplay
     and DeskPad use), sized 1:1 to the region. Sharing apps list it as a
     normal desktop/screen.
   - **Hidden Window:** an invisible window named "Outcut Share" mirrors the
     region for *window* sharing. macOS stops rendering fully offscreen
     windows, so it keeps exactly one pixel on the bottom-right screen
     corner — effectively invisible, never floating.
3. **Local feedback** — a click-through overlay dims everything outside the
   region and draws the configurable border, so you always see what your
   audience sees.

Because the app owns this pipeline, extras happen *inside* it: live
move/resize re-points the running stream (no interruption), pause swaps the
output for a frozen frame or blurred privacy screen, cursor halo/ripples are
drawn into the output only, and recording taps the same frames into an .mp4.

## Caveats

- **Private API:** `CGVirtualDisplay` is not a public API. A future macOS
  could change it — the app then fails with a clear error (and the Hidden
  Window mode keeps working). Not sandboxable / no App Store.
- **Mouse can enter the virtual display** (off the screen edge, usually to
  the right). Move it back the way it went, or rearrange the display in
  *System Settings → Displays*. Hidden Window mode avoids this entirely.
- **Aspect-locked resize in Virtual Display mode:** the display keeps its
  resolution and content scales into it. Growing the region a lot trades
  sharpness; reselect to recreate the display at full size.
- **Permissions:** Screen Recording is required; a guided window with live
  checkmarks appears when it's missing (menu → *Permissions…*). Grants stick
  across rebuilds because builds are signed with a stable identity —
  ad-hoc-signed builds would re-ask every time.
- **Release builds aren't notarized:** right-click → Open once, or
  `xattr -d com.apple.quarantine "Outcut Share.app"`.
- **One region at a time.** Sharing a preset or a new selection replaces the
  active session.
