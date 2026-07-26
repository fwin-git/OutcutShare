# RegionShare — Design

**Date:** 2026-07-26
**Status:** Approved (autonomous session — decisions recorded here for review)

## Purpose

A macOS menu-bar app that lets the user drag-select an arbitrary screen region and
share it as a **standalone virtual monitor** in any screen-sharing app (Zoom, Teams,
Meet, …). Solves the ultrawide problem: share one region of a 49" display instead of
the whole screen or a single window, without switching windows.

While sharing is active, the selected region stays fully visible ("clear") and
everything outside it is dimmed, so the presenter always sees exactly what viewers
see. Dim amount and related options are configurable in a Settings window.

## Feasibility (validated 2026-07-26)

A probe on this machine (macOS 26.5.2, Apple Silicon) confirmed that the private
CoreGraphics `CGVirtualDisplay` API creates a real virtual display that comes online
in `CGGetOnlineDisplayList`. This is the same API used by BetterDisplay, DeskPad and
FluffyDisplay. Because the virtual display is a real display to the window server,
Zoom/Teams list it as a shareable "Desktop", which is exactly the "standalone
monitor" requirement. Trade-off: private API → no App Store, ad-hoc signed local
build. Acceptable for a personal utility.

### Approaches considered

1. **Virtual display + ScreenCaptureKit projection (chosen).** Region appears as a
   real second monitor. Works in every sharing app. Requires private API + Screen
   Recording permission.
2. **Mirror window** (a normal window showing a live region capture; user shares
   that window). No private API, but it is still window-sharing — weaker fit for
   the stated goal. Rejected as primary; can be added later if the private API
   breaks.
3. **Zoom's built-in "Portion of Screen".** Zoom-only, not Teams; rejected.

## Architecture

Swift 6 (Swift 5 language mode where needed for AppKit), AppKit for windows/overlays,
SwiftUI for Settings, ScreenCaptureKit for capture. SPM executable package; a
Makefile assembles `RegionShare.app` (Info.plist, `LSUIElement=1`, ad-hoc codesign
with stable bundle id `com.regionshare.app` so the Screen Recording TCC grant
persists across rebuilds).

### Data flow

```
Select region (drag)                     Settings (UserDefaults)
        │                                        │
        ▼                                        ▼
  ShareSession ──creates──▶ VirtualDisplay (CGVirtualDisplay, sized to region)
        │
        ├──starts──▶ CaptureEngine (SCStream: source display, sourceRect = region,
        │                           excludes RegionShare's own windows)
        │                 │ frames (IOSurface)
        │                 ▼
        ├──shows───▶ ProjectionWindow (borderless, fills the virtual display's
        │                             NSScreen; layer.contents = frame surface)
        └──shows───▶ DimOverlay (click-through window over source display:
                                 dimmed outside region, clear inside,
                                 optional border around region)
```

The user then picks the virtual display ("Desktop 2") in Zoom/Teams.

### Components

- **StatusBarController** — NSStatusItem menu: *Select Region & Share*, *Stop
  Sharing*, *Settings…*, *Quit*. Icon reflects active state.
- **RegionSelector** — one borderless overlay window per screen at shielding level;
  crosshair cursor, drag to select (dimmed backdrop + live rectangle + size label);
  Esc cancels. Returns the region in global coordinates plus its display ID.
  Enforces a minimum region of 64×64 pt.
- **VirtualDisplay** — Swift wrapper over an ObjC bridging header declaring the
  private `CGVirtualDisplay*` classes (resolved via `NSClassFromString` at runtime,
  so a future macOS removing them degrades to a clean error, not a crash). One mode:
  region size in pixels; `hiDPI` set when the source display is Retina. Recreated on
  each new selection; released on stop (display disappears).
- **CaptureEngine** — `SCShareableContent` → `SCContentFilter` for the source
  display excluding this app's windows; `SCStreamConfiguration` with `sourceRect`,
  pixel dimensions, configurable FPS, cursor shown. Delivers frames to the
  projection layer. Handles the permission-missing error by directing the user to
  System Settings → Privacy & Security → Screen Recording.
- **DimOverlay** — borderless, `ignoresMouseEvents`, joins all Spaces, stationary;
  black fill at `dimOpacity` with an even-odd path cut-out over the region;
  optional accent border. Redraws when settings change (live).
- **ShareSession** — owns the above; state machine `idle → selecting → active`;
  tears everything down on stop, display disconnect, or app quit.
- **SettingsStore** — `UserDefaults`-backed observable: `dimOpacity` (0–90 %,
  default 60 %), `showRegionBorder` (default on), `frameRate` (30/60, default 30),
  `dimmingEnabled` (default on). Settings window is a small SwiftUI Form; changes
  apply immediately to an active session (FPS change restarts the stream).

## Error handling

- No Screen Recording permission → alert + open the Privacy pane; session aborts
  cleanly.
- `CGVirtualDisplay` classes missing / creation fails → alert explaining the macOS
  incompatibility; nothing else is left running.
- Source display disconnects or capture stream stops with error → session stops,
  menu returns to idle.
- Selection smaller than minimum → selection simply doesn't complete.

## Testing

- `swift test` unit tests for pure logic: region normalization from drag points,
  minimum-size enforcement, AppKit↔CoreGraphics coordinate conversion, virtual
  display mode computation (pixel size / hiDPI), settings defaults & persistence.
- UI, capture and TCC flows are verified manually (build, launch, select, confirm
  virtual display online and dimming correct); an automated smoke test launches the
  bundled app and checks it stays running.

## Out of scope (YAGNI)

Multiple simultaneous regions, region move/resize after selection (reselect
instead), global hotkeys, audio, recording, App Store distribution, dim color
choice (black only).
