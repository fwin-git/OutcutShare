# Raycast extension for Outcut Share — design

Date: 2026-07-28. Status: approved by user (mechanism, command set, preset
UX and repo location chosen via Q&A).

## Goal

Trigger Outcut Share's main actions from Raycast: share last region, share
a preset, start selection (or the Virtual Monitor), stop, pause/resume,
start/stop recording, set follow mode, switch share mode (only while not
sharing), and toggle the presenter options (preview window, hotbar, cursor
highlights, dimming). Appearance/style settings stay out of scope.

The app has no external control surface today, so the work has two halves:
a `outcutshare://` URL scheme in the app, and a Raycast extension that
opens those URLs.

## Part 1 — app-side URL scheme

### Registration

- `Support/Info.plist` gains `CFBundleURLTypes` with scheme `outcutshare`.
- `AppDelegate` registers a `kAEGetURL` Apple-Event handler in
  `applicationWillFinishLaunching` (must be *will*, so URLs that launch the
  app are delivered; `open outcutshare://…` auto-starts the app when it is
  not running). The demo-windows helper path is unaffected — the handler is
  registered before the arg check but only dispatches session actions.

### Parsing

New `Sources/OutcutShare/URLCommands.swift`: pure, unit-tested parser.

```swift
enum URLCommand: Equatable {
    case select              // outcutshare://select
    case shareLast           // outcutshare://share-last
    case preset(id: String?, name: String?) // outcutshare://preset?id=…|name=…
    case stop                // outcutshare://stop
    case togglePause         // outcutshare://pause
    case toggleRecording     // outcutshare://record
    case follow(FollowMode)  // outcutshare://follow?mode=off|activeWindow|cursor
    case shareMode(ShareMode)// outcutshare://share-mode?mode=virtualDisplay|hiddenWindow|virtualMonitor
    case toggle(ToggleOption)// outcutshare://toggle?option=preview|hotbar|cursorHighlights|dimming

    static func parse(_ url: URL) -> URLCommand?
}
```

`mode`/`option` values match enum raw values, matched case-insensitively.
`preset` requires at least one of `id`/`name`; malformed URLs parse to
`nil` and are ignored (logged, no alert — stray links must not spam).

### Dispatch (AppDelegate, mirrors the hotkey switch)

- `.select` → `session.startSelection()` (covers Virtual Monitor start —
  `startSelection` already branches on the share mode)
- `.shareLast` → `session.shareLastRegion()`
- `.preset` → look up in `SettingsStore.shared.presets`: by `id` (UUID
  string) first, else by name (exact, then case-insensitive first match) →
  `session.sharePreset(_:)`. Not found → small alert naming the query.
- `.stop` / `.togglePause` / `.toggleRecording` → the session methods
  (recording toggle is a silent no-op while idle, same as the hotkey).
- `.follow` → `session.setFollow(mode:)`.
- `.shareMode` → guard the session is fully idle (new read-only
  `ShareSession.isIdle`, i.e. `state == .idle` — selecting also rejects);
  then set `SettingsStore.shared.shareMode`. While not idle → alert
  "Stop sharing first to switch the share mode."
- `.toggle` → flip `previewWindowEnabled` / `hotbarEnabled` /
  (`cursorHighlight` + `clickRipples` set to the flipped value together) /
  `dimmingEnabled`. Live sessions pick changes up via the existing
  `settingsChangedNotification` diffing.

## Part 2 — Raycast extension (`raycast/` in this repo)

TypeScript extension built on `@raycast/api` (name `outcut-share`, single
extension, one command file each under `raycast/src/`).

No-view commands — open the deep link, then `showHUD`:

| Command | URL |
| --- | --- |
| Share Last Region | `share-last` |
| Select Region & Share | `select` |
| Stop Sharing | `stop` |
| Pause / Resume Sharing | `pause` |
| Start / Stop Recording | `record` |
| Toggle Preview Window | `toggle?option=preview` |
| Toggle Hotbar | `toggle?option=hotbar` |
| Toggle Cursor Highlights | `toggle?option=cursorHighlights` |
| Toggle Dimming | `toggle?option=dimming` |

List commands:

- **Share Preset** — lists current presets by name (plus region size as
  subtitle); Enter opens `preset?id=<uuid>`. Empty state: "No presets saved
  yet — save one from the Outcut Share menu."
- **Set Follow Mode** — Off / Active Window / Cursor, current value
  check-marked; Enter opens `follow?mode=…`.
- **Set Share Mode** — Hidden Window / Virtual Display / Virtual Monitor,
  current value check-marked; Enter opens `share-mode?mode=…`. Item
  accessory notes it applies only while not sharing.

### Reading app state (`raycast/src/defaults.ts`)

`defaults export com.outcutshare.app -` (via `execFile`; goes through
`cfprefsd`, so never stale) → minimal XML-plist value extraction:

- `presets`: `<data>` blob → base64-decode → `JSON.parse` (the same JSON
  `JSONEncoder` wrote): `{ id, name, region: { width, height, … } }`.
- `followMode`, `shareMode`: `<string>` values (absent key → defaults
  `off` / `virtualDisplay`, matching `SettingsStore` fallbacks).

The extractor is a pure function (plist text in → values out), covered by
`node --test`.

### Errors

`open()` failing (app not installed / scheme unregistered) → failure
toast. Everything else is fire-and-forget; the app is responsible for
user-visible rejections (mode switch while sharing, unknown preset).

## Part 3 — docs & loading

- `docs/raycast.md` (linked from the README docs table + feature list):
  what the extension does, install: Raycast + Node ≥ 20, then
  `cd raycast && npm install && npm run dev` — imports the extension in
  development mode; it stays available after stopping the dev server.
  Also documents the URL scheme itself (usable from any automation tool).
- `raycast/README.md`: short pointer to the same.
- AGENTS.md: note that `raycast/` exists and that URL grammar changes must
  update both sides + docs.

## Testing

- XCTest: `URLCommandsTests` — every command, parameter variants,
  case-insensitivity, malformed URLs → `nil`. TDD.
- `node --test` for the plist extractor (`npm test` in `raycast/`). TDD.
- E2E after `make app` + relaunch: drive every route via
  `open "outcutshare://…"` from the terminal; user confirms visuals.
  Preset/state listing verified against the user's real presets.
- Zero warnings; feature branch `feature/raycast-extension`, `--no-ff`
  merge, build & relaunch after the milestone. No release unless the user
  says so.

## Out of scope (YAGNI)

State readback into Raycast (pause/recording indicators, menu-bar-icon
state), appearance/style settings, Settings/Permissions windows, Raycast
store packaging, pause/resume as separate one-way commands.
