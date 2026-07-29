# AGENTS.md — working on Outcut Share

Orientation for any agent session picking this project up. User-facing docs
live in `docs/` and the README; this file is about *how we build it*.

## What the app is

Outcut Share is a macOS menu-bar app that shares an **arbitrary screen
region as its own monitor** in Zoom/Teams/Meet. Built for ultrawide users:
share one clean slice instead of the whole 5120×1440, without being locked
to a single app window. Everything else grew around that core:

- **Three share modes** (`ShareMode`): a **virtual display** created via the
  private `CGVirtualDisplay` API (viewers pick it under "share screen"), a
  **hidden window** pinned 1×1 px on a screen corner (picked under "share
  window" — macOS stops rendering fully offscreen windows, hence the pixel),
  and a **virtual monitor** — a standalone empty screen the user drags
  windows onto (regionless; the prominent preview panel is the window into
  it, with AX-powered drag-in/out and magnet snap zones; Accessibility
  permission optional, only for the window moving).
- **Local feedback**: click-through dim overlay outside the region with a
  configurable border; the region stays clear.
- **Live region control**: move/resize while sharing (stream is re-pointed
  via `SCStream.updateConfiguration`, never restarted), selection/adjust
  overlays with macOS-screenshot-style modifiers (Space window-pick, Space
  drag-freeze, ⇧ aspect, ⌃ standard-size snapping with previews), follow
  mode (active window or cursor; snap/glide; optional resize), presets +
  last-region recall, floating hotbar, privacy pause (freeze or blurred
  privacy screen), viewer-only cursor emphasis, notification/app hiding via
  capture exclusion, region recording to mp4, global hotkeys (Carbon —
  needs no permissions), guided permissions onboarding, settings previews.

## How it works — the pipeline

```
RegionSelector (drag/pick overlay)             SettingsStore (UserDefaults)
        │                                              │ settingsChangedNotification
        ▼                                              ▼
  ShareSession (state machine: idle → selecting → active; owns everything)
        ├── VirtualDisplay (private CGVirtualDisplay via CVDApi factory)
        ├── CaptureEngine (SCStream; sourceRect = region; excludes own app,
        │        Notification Center, user's hidden apps — by APPLICATION)
        │        ├── onFrame → LiveFrameWindow (projection on virtual screen
        │        │             OR hidden mirror window; privacy screen, halo)
        │        └── onSampleBuffer → RecordingEngine (AVAssetWriter)
        ├── DimOverlay (click-through, even-odd cutout, styled border)
        ├── HotbarController (NSPanel, quick actions)
        ├── PreviewWindowController (floating "what viewers see" panel;
        │        docks outside region, aspect-locked resize, pause corner
        │        button, ≡ grabber; always above dim)
        ├── FollowController (timer; window/cursor targets → setRegionRect)
        ├── CursorEmphasisController (halo/ripples drawn on OUTPUT only)
        └── RegionMover (adjust overlay: move/resize/pick)
```

Key invariants:

- **ShareSession is the single orchestrator.** UI components never talk to
  each other; they call session methods, session calls them back. UI state
  fan-out happens via `notifyUI()` — always use it, never `onStateChange?()`
  directly (a stale-icon bug came from exactly that).
- **All chrome is excluded from capture** (application-level exclusion incl.
  own bundle id → covers other instances and future windows). Overlay and
  hotbar are created *before* `capture.start` so the first filter knows them;
  a re-apply at 0.8 s/2 s covers ScreenCaptureKit's app-registration lag.
- **Live changes coalesce**: `setRegionRect` funnels move/resize/follow into
  one throttled `updateConfiguration` path (one in-flight, newest wins).
- **Geometry.swift holds all pure math** (selection, clamping, aspect
  fitting, snapping, hotbar placement, dead zones) — fully unit-tested; the
  AppKit layers stay thin and untested.

## Hard-won gotchas (do not relearn these)

- **Ad-hoc signing breaks TCC**: every ad-hoc build has a new identity →
  Screen Recording re-prompts. `make app` signs with the first *Apple
  Development* identity (stable designated requirement). Never regress this.
- **Transparent windows are click-through by alpha**: the window server
  hit-tests per-pixel. Overlays must set `ignoresMouseEvents = false`
  *explicitly* (disables that) AND paint a 1%-alpha floor.
- **`acceptsFirstMouse` + key reclaiming** on overlays: otherwise the first
  click is eaten as app activation and Space/Esc go to other apps.
- **Panel property order matters**: `isFloatingPanel` silently resets
  `level`. Set `level` last. Hotbar sits at screenSaver+1 (above the dim).
- **System tooltips render below screenSaver-level windows** — draw tooltips
  inside the panel. Never insert/remove **material views** dynamically in a
  panel (window-server backdrop rebuild → beachball + eaten clicks); keep
  them in the tree and swap opacity.
- **SwiftUI timers must live in `@State`** (`Timer.publish...autoconnect()`
  as plain `let` gets recreated every re-render and never fires once
  anything re-renders frequently).
- **Space auto-repeats**: swallow repeat keyDowns or macOS beeps per repeat.
- **Debug binary vs bundle have separate defaults domains** (`OutcutShare`
  vs `com.outcutshare.app`). Tests write the CLI domain via
  `defaults write OutcutShare …` — always clean up after.
- **The user often runs the release app while you test the debug build.**
  Their overlays/hotbar are a *different process* — before v1.5 fixes they
  appeared in your test captures. Don't chase ghosts; ask the user.
- **macOS 26 leaks observation-tracking registrations on every render of a
  hosted settings page** (~6 per `NSHostingView.layout` pass; shows up as
  `Observation._ManagedCriticalState` growth in `heap`). Publishing 20 Hz
  demo progress through a model the whole page observed grew those tables
  until the main thread crawled (minutes!). High-frequency state must live
  on its own tiny observable that only the small view observes
  (`DemoProgress` → ring), and canvas timers gate on visibility.
- **NSTabViewController's toolbar items retain the controller in a cycle
  that outlives the window** — dropping references after close keeps every
  page and its timers alive forever. `SettingsWindowController` tears the
  tab items out on close; verify with `--close-settings-after` + `heap`
  (want 0 `NSHostingController`, 0 live `TimerPublisher`).
- **macOS moves a left/right Dock onto the outermost display of that side**
  — a virtual display arranged there steals the Dock (and shares it!).
  `activateMonitor` places the monitor OPPOSITE the Dock via
  `CGConfigureDisplayOrigin` and re-resolves the NSScreen afterwards (the
  arrangement propagates with a lag). Also: `NSScreen.main` is the KEY
  window's screen — poisoned once anything on the virtual display gains
  focus; use `NSScreen.screens.first` or the panel's screen instead.
- **Cursor teleports**: `CGWarpMouseCursorPosition` suppresses hardware
  deltas ~0.25 s (motion freezes) — post a `.mouseMoved` CGEvent instead.
  `CGRect.contains` excludes max edges: a cursor pinned at a display's
  top/right sits exactly ON maxY/maxX.
- **Parallel agent sessions have collided here twice** (file reverts, push
  races). If another agent is active, work in a separate git worktree.
- Screenshots for verification: `screencapture -x out1.png out2.png`
  captures each display to consecutive files; `sips -c H W --cropOffset Y X`
  (Y first!). Some window-server layers may not appear in captures even when
  visible to the user — treat "user confirms visually" as ground truth.

## Development workflow (established with the user)

1. **Feature branch per milestone** (`feature/...` or `fix/...`); never
   implement on `main` directly.
2. **TDD the pure logic** (geometry/settings/model): failing test → impl →
   green. UI layers are verified at runtime instead.
3. **Verify end-to-end before merging** using the debug flags (below) and
   screenshot inspection. Zero build warnings is the standard.
4. **Merge with `--no-ff` to `main`, push** (`origin` =
   https://github.com/fwin-git/OutcutShare, account `fwin-git`; commits are
   authored as `fwin-git <253688468+fwin-git@users.noreply.github.com>` —
   repo-local git config, keep it).
5. **After every milestone: build & relaunch** so the user always runs the
   latest: `make app && pkill -x OutcutShare; open build/OutcutShare.app`.
6. **NEVER cut a release unless the user explicitly says so.** Polish
   collects across milestones; a version number mentioned in passing is a
   target, not a trigger. When told: `make release` (derives the version
   from conventional commits, tags, pushes; CI publishes with a changelog
   generated from `feat:`/`fix:` subjects — commit messages are therefore
   user-facing: plain, feature-oriented, no marketing).

## Debug flags (the E2E test harness)

```
--vd-test[=2x]                          virtual display on/off(line) check
--share-test=x,y,w,h,secs[,vd|window|monitor]   full pipeline, frame count
   (monitor ignores the rect — regionless virtual-monitor session)
   companions: --move-by=dx,dy  --resize-by=dw,dh  --pause-at=t1,t2
               --record-at=t1,t2  --screenshot-at=t1,t2  --zoom-at=t1,t2
               --follow=activeWindow|cursor  --preview
--hotkeys-test                          registered shortcuts
--permissions-test                      permission status line
--show-settings[=tab] [--dim-preview]   open a settings pane
   companion: --close-settings-after=secs (teardown/perf verification)
--demo=monitor|region|follow            record a feature showcase to
   ~/Movies/OutcutShare/Demos (16:9 stage, helper-process fake windows,
   synthetic input — takes over the mouse ~30 s; needs AX; NEVER touch
   non-helper windows in choreography, see DemoHarness.swift)
--show-selector / --show-permissions    open those UIs
--result-card-test=/path/img-or-mp4     capture-result preview card, standalone
   companions: --open-trim (show the trim UI)  --trim-test=in,out (export range)
```

Coordinates are AppKit (bottom-left origin) on the main screen. The shell
this project is developed in already holds Screen Recording permission, so
`--share-test` works headlessly; posting synthetic input does NOT (no
Accessibility) — anything drag/hover-based needs the user's hands.

## Code conventions

- Swift 5 language mode (`nonisolated(unsafe)` where AppKit/queues demand),
  `@MainActor` on UI classes, zero warnings policy.
- Settings: every option is a `@Published` var on `SettingsStore` with
  `didSet` → `defaults.set` + `notifyChange()`; enums are `String`-raw.
  Live consumers observe `settingsChangedNotification`. Session-applied
  options are diffed in `settingsDidChange()` (track `activeX` copies).
- Comments state non-obvious constraints only (the "why", never the diff).
- Tests: XCTest in `Tests/OutcutShareTests`; settings tests use a throwaway
  `UserDefaults(suiteName: UUID)` with tearDown cleanup.
- Files stay focused (one component per file); shared drawing/logic gets
  extracted (`SnapPresets`, `RegionPreviewCanvas`, `Geometry`) rather than
  duplicated.

## Layout

```
Sources/OutcutShare/        app code (one component per file)
Sources/CVirtualDisplay/    ObjC declarations + NSClassFromString factory
Tests/OutcutShareTests/     unit tests (pure logic)
Resources/Assets.xcassets/  app icon (compiled via actool in make app)
Support/Info.plist          bundle template (version stamped by Makefile)
Scripts/changelog.sh        feat/fix → consumer changelog
Scripts/release.sh          conventional-commit version bump + tag + push
.github/workflows/          ci.yml (tests) + release.yml (tag → release)
docs/                       user-facing docs, linked from README
raycast/                    Raycast extension (TypeScript; URL-scheme client)
```

The app is remote-controllable via the `outcutshare://` URL scheme
(`URLCommands.swift` parses, `AppDelegate` dispatches). Grammar changes
must update `URLCommands.swift`, the `raycast/` commands, and
`docs/raycast.md` together.

The user's machine: Dell U4919DW ultrawide (5120×1440 @1×, resolution has
changed mid-project before), macOS 26, German locale. They actively use the
app during development — expect live sessions during your tests.
