# RegionShare

A macOS menu-bar app that shares an **arbitrary screen region as its own
monitor**. Drag-select any part of your screen — the region appears as a
virtual display ("Region Share") that you can pick in Zoom, Teams, Meet or any
other screen-sharing tool, exactly like a real second monitor.

Made for ultrawide displays: share one clean, viewer-sized slice of your
5120×1440 instead of the whole desert — without being locked to a single
window or having to switch windows mid-presentation.

While sharing, the selected region stays fully clear on your screen and
everything outside it is dimmed, so you always see exactly what your audience
sees.

## Build & run

```sh
make app     # builds build/RegionShare.app
make run     # builds and launches it
make test    # unit tests
```

Requires Xcode command line tools on macOS 14+ (developed on macOS 26).

## First run

1. Launch the app — a dashed-rectangle icon appears in the menu bar.
2. If the **Screen & System Audio Recording** permission is missing, a guided
   permissions window opens automatically with live-updating checkmarks: click
   *Request Permission* (or enable RegionShare in the System Settings pane it
   opens for you) and the checkmark flips green by itself; a *Relaunch* button
   appears if macOS needs a fresh start to apply the grant. The window is also
   available anytime via menu → **Permissions…**.
3. Choose **Select Region & Share** and drag a rectangle (Esc cancels).
4. Depending on the **Share as** setting:
   - **Virtual Display** (default): a display named **Region Share** comes
     online sized to your region; your sharing app lists it as another
     desktop/screen — share that one.
   - **Hidden Window**: an invisible window named **Region Share** mirrors the
     region live; pick it in your sharing app's *window* list. Nothing floats
     on your screen — the window keeps exactly one pixel in the bottom-right
     screen corner (macOS stops rendering fully offscreen windows).
5. **Move / Resize Region** (⌘M in the menu) adjusts the region while
   sharing — viewers see the content follow live, the share never interrupts.
   Drag inside the region to move it, drag a corner handle to resize; arrow
   keys nudge (Shift = 10 pt), Return commits, Esc puts the region back.
   Resizing is free in Hidden Window mode; in Virtual Display mode it is
   locked to the region's aspect ratio (the virtual display keeps its
   resolution and the content scales into it, so the sharing app never sees a
   display change).
6. **Stop Sharing** removes the virtual display / hidden window and the
   dimming.

## Settings

Menu bar → **Settings…** — three pages:

**General**

| Setting | Effect | Default |
| --- | --- | --- |
| Share as | Virtual Display (share a screen) or Hidden Window (share a window) | Virtual Display |
| Frame rate | Capture rate of the shared region (30/60 fps) | 30 fps |

**Appearance**

| Setting | Effect | Default |
| --- | --- | --- |
| Dim screen outside region | Toggles the dimming overlay | on |
| Dim amount | 0–90 % black over everything outside the region | 60 % |
| Show border around region | Frame just outside the region | on |
| Border color | Any color incl. opacity | red |
| Border style | Solid, dashed or dotted | dashed |
| Border thickness | 1–10 pt | 3 pt |
| Border corner radius | 0–30 pt (also rounds the dim cutout) | 8 pt |

**Shortcuts** — system-wide hotkeys (no extra permissions needed), recordable
to any key combination; click *Record*, press the combo (Esc cancels), ✕
clears a binding:

| Action | Default |
| --- | --- |
| Select Region & Share | ⌃⌥⌘S |
| Move / Resize Region | ⌃⌥⌘M |
| Stop Sharing | ⌃⌥⌘X |

Assigning the same combo twice shows a warning on both rows; only the first
action keeps the binding until the conflict is resolved. A combo without any
modifier (except F-keys) also gets a caution, since it would swallow that key
system-wide.

Changes apply live to an active session. The dim overlay and border are drawn
outside the shared area and excluded from capture — viewers never see them.
(The capture itself always stays a sharp rectangle; the corner radius only
styles what you see locally.)

## How it works

- A virtual display is created through the private CoreGraphics
  `CGVirtualDisplay` API (the same mechanism BetterDisplay and DeskPad use),
  sized 1:1 to the selected region.
- ScreenCaptureKit captures just the region (cursor included) and projects the
  frames onto a window filling the virtual display.
- A click-through overlay dims everything outside the region on your real
  screen.

## Signing & permission persistence

macOS ties the Screen Recording grant to the app's code signature. `make app`
therefore signs with your first *Apple Development* identity when one exists
(override with `make app CODESIGN_ID=…`), so the grant survives rebuilds.
Without any identity it falls back to ad-hoc signing — which changes every
build and makes macOS re-ask each time. If you're upgrading from an earlier
ad-hoc build and see repeated permission prompts, remove the stale entry once:

```sh
tccutil reset ScreenCapture com.regionshare.app
```

then grant again via the permissions window.

## Caveats

- The `CGVirtualDisplay` API is private; a future macOS could change it. The
  app fails with a clear error message in that case rather than crashing.
  Not sandboxable / not App Store distributable.
- The virtual display is a real display to macOS: your mouse can travel onto
  it (off the edge of your screen, usually to the right). If your cursor
  "disappears", move it back the way it went. You can rearrange the virtual
  display's position in *System Settings → Displays* while sharing. The
  Hidden Window mode avoids all of this — use it if the extra display gets in
  your way.
- One region at a time. Moving and resizing work live via **Move / Resize
  Region**. In Virtual Display mode, growing the region means macOS renders
  more content into the same display resolution — if viewers need more
  detail at the larger size, reselect so the display is recreated at the new
  size.
- Changing "Share as" while sharing restarts the session — re-pick the
  screen/window in your sharing app afterwards.

## Development

`swift test` covers the pure logic (geometry, settings). Two debug flags help
with end-to-end verification without clicking through the UI:

```sh
.build/debug/RegionShare --vd-test                             # virtual display only
.build/debug/RegionShare --share-test=100,100,800,600,8        # full pipeline, 8 s
.build/debug/RegionShare --share-test=100,100,800,600,8,window # hidden-window mode
.build/debug/RegionShare --share-test=100,100,800,600,12,vd --move-by=700,300 # live move mid-run
.build/debug/RegionShare --share-test=100,100,800,600,12,window --resize-by=200,100 # live resize mid-run
```
