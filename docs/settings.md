# Settings reference

Menu bar → **Settings…** — eight pages.

## General

| Setting | Effect | Default |
| --- | --- | --- |
| Share as | Virtual Display (share a screen), Hidden Window (share a window) or Virtual Monitor (separate screen, see below) | Virtual Display |
| Monitor resolution | Size of the Virtual Monitor screen | 1920 × 1080 |
| Layout grid with | Modifier held during a preview drag to summon the 3 × 3 layout grid | ⇧ Shift |
| Crisp text (Retina output) | Gives the virtual display 2× pixel density — sharpest with Retina sources, reduces compression artifacts otherwise; more bandwidth. Virtual Display mode only | off |
| Follow movement | Snap or smooth glide when follow mode moves the region | Glide |
| Resize region to followed window | Follow mode adopts the window's size (aspect-fitted in Virtual Display mode) | on |
| Follow | Off / Active Window / Cursor (also in menu bar → Follow) | Off |
| Show floating hotbar | Quick-action bar next to the region: stop, pause, record, screenshot, highlights, preview, resize, save preset, follow (split button — icon toggles, label picks the mode). Auto-positions below → side → top; drag the ≡ grabber to place it manually; ✕ hides it until re-enabled. Stays parked while cursor follow runs, so the moving region can't push it out of reach | on |
| Show shared-output preview | Small floating window with exactly what viewers see — no need to keep Zoom/Teams open. Also toggled by the hotbar's eye button | off |
| Share window title | The name sharing apps list for the hidden share window in their window pickers (Hidden Window mode) | Outcut Share (Share Region) |
| Viewer zoom magnification | How far ⌃⌥⌘Z zooms the shared picture toward the cursor (1.5×/2×/3×); the zoom glides and gently tracks the cursor, viewers-only | 2× |
| Capture frame rate | 30/60 fps — applies to both the shared picture and recordings | 30 fps |
| Launch at login | Start with macOS (app bundle only) | off |
| Show Dock icon while active | Dock, ⌘-Tab and Force Quit presence while sharing or settings open | off |
| Version | Current version + build for support | — |

The **preview window** docks outside the region (right → left → below →
above, wherever there's free space) so it never covers what you're
sharing. Drag it anywhere by its picture (the ≡ grabber marks the spot),
resize it from the edges — the region's aspect ratio is kept — and use the
pause button in its top-right corner to pause/resume sharing even with the
hotbar hidden. It always floats above the dimming. The choice persists.

Follow mode itself is enabled per-session from the menu bar:
**Follow → Active Window / Cursor**.

![Follow mode tracking the active window, then the cursor](media/demo-follow.gif)

### Virtual Monitor mode

![Virtual Monitor — drag windows in, grid layout, pull-out](media/demo-monitor.gif)

The safest way to share: a **separate, empty screen**. Nothing from your
real display is ever shared — only windows you deliberately place on the
virtual monitor. Start it from the menu bar (*Start Virtual Monitor &
Share*), then pick the new screen under “share screen” in Zoom/Teams.

A **large preview panel** opens centered on your screen — your window into
the monitor. With the optional **Accessibility** permission:

- **Drag any window onto the panel** and drop it — it moves to the virtual
  monitor, right where you dropped it (the panel highlights while you
  hover).
- **Grab a window inside the picture and drag** — a live ghost of the
  window rides your cursor. Drop it anywhere on the monitor to move it,
  or drag it off the panel and it pops back onto your real screen under
  the cursor (on your current Space).
- **Hold the layout modifier (⇧ by default, configurable) while
  dragging** for the 3 × 3 grid: drop in a cell to fill it, or sweep from
  one cell to another to span any block — a full bottom row, a two-thirds
  column, whatever the sweep covers becomes the window's new frame.
- **Control mode** — the cursor button in the panel's top-right corner:
  while on, clicking the picture hands your cursor to the corresponding
  spot on the monitor, where it works natively — browse folders, drive a
  browser, select text. A teal glow on the preview reminds you of the way
  back: push the cursor against **any edge of the virtual screen** and it
  returns to the preview panel.

The panel moves via its ≡ grabber in this mode and resizes from its
edges; pausing covers the whole virtual screen with the privacy note. You
can also simply move your mouse onto the virtual monitor and arrange
windows there like on any screen.

## Appearance

| Setting | Effect | Default |
| --- | --- | --- |
| Dim screen outside region | Local dimming overlay | on |
| Dim amount | 0–90 % black outside the region | 60 % |
| Highlight cursor | Halo around the cursor — visible to viewers only | on |
| Show click ripples | Click animation — viewers only | on |
| Show border around region | Frame just outside the region | on |
| Border color / style / thickness / radius | Any color incl. opacity · solid, dashed, dotted · 1–10 pt · 0–30 pt | red · dashed · 3 pt · 8 pt |

Dimming and border are local-only: they're excluded from what viewers see.

## Privacy

| Setting | Effect | Default |
| --- | --- | --- |
| When paused, viewers see | Frozen last frame, or a blurred privacy screen with a slashed-eye note | Privacy screen |
| Hide notification banners from viewers | Notification Center is excluded from the capture — banners stay visible on your screen but never appear in the shared picture | on |
| Hidden apps | Windows of the apps you add never appear in the shared picture; viewers see what's behind them. “Add App…” opens a searchable list of installed apps (sensitive apps suggested first, Browse… for unusual locations). Changes apply live | empty |

## Recording

| Setting | Effect | Default |
| --- | --- | --- |
| Save recordings to | Folder for .mp4 recordings | ~/Movies/OutcutShare |
| Record system audio | The captured apps' sound as an AAC track (Outcut Share itself excluded) | on |
| Record microphone | Your voice as a second track; asks for mic permission on the first recording | off |

Privacy pause silences both audio tracks together with the picture.

## Screenshots

Taken with the hotbar's camera button while sharing — the picture is the
shared output itself, including privacy exclusions. If the region outline
has a corner radius, the screenshot's corners are rounded to match.
Files are named `screenshot_YYYY-MM-DD_HH-mm` (recordings:
`recording_…`). After every capture — screenshots and finished
recordings alike — a small preview card folds out under the hotbar for a
few seconds: show in Finder, peek large with playback (Quick Look,
tap the eye again to close) or delete, straight from its corner buttons.
Recordings show a duration + file-size pill; hovering the card keeps it
open.

The card's scissors button opens **drag-to-trim**: a filmstrip with two
handles — drag anywhere on the strip and the nearer handle follows,
while the big preview scrubs to the frame under it. ✓ saves the
selection as `…_trim.mp4` next to the original (which stays untouched;
no re-encode, audio kept), ✕ cancels.

| Setting | Effect | Default |
| --- | --- | --- |
| Save screenshots to | Folder for region screenshots | ~/Pictures/OutcutShare |
| Maximum size | Longest edge in pixels (Original / 1024 / 2048 / 4096); never upscales | Original |
| Quality | 100 % saves a lossless PNG; anything below saves a JPEG at that quality | Lossless PNG |
| Add a smooth drop shadow | Renders onto a soft-shadow canvas (PNG keeps it transparent, JPEG flattens to white) | off |

## Presets

Rename or delete saved regions. Save new ones while sharing via menu bar →
*Presets → Save Current Region as Preset…*. The first nine are shared
instantly with ⌃⌥⌘1–9; presets remember their share mode and fall back to
the best-matching screen if their display is gone.

## Shortcuts

See [hotkeys.md](hotkeys.md).
