# Demo showcase clips: viewer zoom, capture workflow, Raycast still

2026-07-29. Everything shipped in v1.12–v1.15 is invisible in the README's
feature showcase. This adds two new self-recorded clips and one still image,
plus the docs updates that surface them. Scope approved by the user
("build out the full demo harnesses & record the clips for viewer zoom,
capture workflow & raycast extension", with the drag-a-capture-out-of-the-card
beat explicitly requested).

## Goals

1. `--demo=zoom` — viewer zoom (⌃⌥⌘Z) tracking the cursor, mirrored into the
   mock call, then a live preset switch gliding the region mid-share.
2. `--demo=capture` — the capture workflow on the hotbar: screenshot → preview
   card → **drag the file out of the card into a chat window**, then record →
   stop → drag-to-trim with scrub preview → save.
3. `--demo=raycast` — a still PNG of the Outcut Share command list in
   Raycast's root search for `docs/raycast.md`.
4. README gains two showcase sections with the new GIFs; `docs/development.md`
   and `AGENTS.md` list the new scenarios; a small script pins the mp4→GIF
   conversion (900 px wide, 12.5 fps, palettegen — matches the existing GIFs).

Non-goals: OCR clip (clipboard results don't film), vertical-hotbar clip and
pause-screen clip (can ride along in future clips); no new app features.

## Approach

Extend `DemoDirector` (DemoHarness.swift) with three scenarios, following the
existing choreography style: 16:9 stage, helper-process fake windows, keystroke
HUD chips introducing each beat, `SampleRetimer` baked-in playback speed,
strictly `helperWindows(in:)` for anything touched. Alternatives considered:
scripted AppleScript/CGEvent driving from the shell (rejected — the shell has
no Accessibility, the app bundle does, and the in-app director already owns
stage/recording/HUD), and screen-recording the real UI by hand (rejected —
not reproducible, personal content risk).

### Shared plumbing: demo anchor hooks

Choreography must click real UI (hotbar buttons, card chips, trim strip),
whose layout lives in SwiftUI. New `DemoState` fields, populated only while
`DemoState.active`:

- `DemoState.hotbarItems: [String: CGRect]` — AppKit screen rects of hotbar
  buttons, keyed by their existing help strings ("Screenshot shared region",
  "Start recording", "Stop recording", …). `HotbarView` already collects
  per-item anchors in `BarItemBounds`; a demo-only side channel reports the
  resolved rects (hosting-view coordinates) to `HotbarController`, which
  converts them through its panel frame.
- `DemoState.cardItems: [String: CGRect]` — same for the capture card: chip
  help strings ("Trim recording", "Save trimmed copy", …) plus `__image__`
  (the drag-out surface) and `__timeline__` (the trim strip), reported by
  `CaptureResultView` → `CaptureResultController`.

Pure conversion (SwiftUI top-left local rect + panel frame → AppKit screen
rect) goes into `Geometry.demoAnchorRect(local:panelFrame:)`, TDD'd. The
reporting path is inert outside demo runs (guarded by `DemoState.active`).

The trim strip needs no per-handle anchors: its gesture grabs whichever handle
is nearer the press, so pressing near an end of `__timeline__` and dragging
is exact enough.

### `--demo=zoom`

Stage like the region demo: hidden-window mode, preview window off, mock call
(`DemoMeetMock`) on the stage's right, `session.demoFrameTap` feeding the true
share feed into the call mirror. Helper windows arranged (via `WindowMover`,
before recording starts) so notes + metrics fill a 16:9-ish region on the
left; share starts directly via `session.startSharing` (selection theater is
the region clip's job).

Beats:
1. Chip "⌃⌥⌘Z — Viewers zoom in, your screen stays put". Cursor glides onto
   the metrics bars, `session.toggleZoom()` — the call mirror punches into a
   2× window while the stage is visibly unchanged.
2. Cursor glides along the notes checklist — the zoom window tracks it
   (dead-zone glide), the mirror pans.
3. `session.toggleZoom()` — mirror glides back out.
4. Chip "Preset — the region glides over, the share never stops".
   `session.sharePreset(...)` with a same-size region over the chat window
   (same display + mode → live glide path). The region outline glides across
   the stage; the mirror follows without the share dropping.
5. Stop. Speed 1.5×.

### `--demo=capture`

Hidden-window mode, hotbar enabled (setting saved/restored), no call mock —
the card is the star. Region over the metrics window; chat window sits outside
the region as the drop target. Hotbar appears at the region edge; its button
rects come from `DemoState.hotbarItems`.

Beats:
1. Chip "Screenshot". Cursor clicks the hotbar camera button → card folds out
   under the hotbar; cursor moves onto the card (hover pauses the 3 s
   countdown).
2. Chip "Drag it anywhere". Drag from the card's image into the chat helper
   window; the chat shows the screenshot as a new attachment bubble.
   `DemoChatView` (helper process) registers as a file-drop target — a real
   cross-process drag, the same machinery as dropping into Slack.
3. Chip "Record". Click the record button (red state), stage action for ~4 s
   (cursor moves over the notes; a helper window gets nudged so the filmstrip
   thumbnails differ), click stop → card pops with the video + duration pill.
4. Chip "Trim". Hover the card, click the scissors chip → card expands with
   the filmstrip. Press near the strip's right end, drag left (scrub preview
   follows), then the left end inward. Click ✓ → exporting spinner → trimmed
   copy saved.
5. Card auto-hides, stop. Speed ~1.6×.

### `--demo=raycast`

Produces a PNG, not a video: activate Raycast's root search (deeplink /
`open -a Raycast`; exact invocation determined at implementation), type
"outcut share" with synthetic keystrokes (letters chosen QWERTZ-safe; the app
binary holds AX), wait for results, locate the Raycast window via
`CGWindowList`, capture it with `screencapture -l<windowID>`, then Esc to
dismiss. Output lands next to the demo mp4s. Prerequisite: the extension is
imported in Raycast dev mode (`cd raycast && npm run dev`, persists after
Ctrl-C) — verified/refreshed before capturing. The choreography touches no
other app and presses no Enter. This bends "only helper windows" knowingly
and minimally: opening a launcher, typing a query, Esc.

### GIFs and docs

- `Scripts/demo-gif.sh in.mp4 out.gif`: ffmpeg `fps=12.5,scale=900:-2` with
  palettegen/paletteuse — the parameters the existing GIFs use, now pinned.
- README: new showcase section "Viewer zoom & live presets" (after Region
  selection) with `docs/media/demo-zoom.gif`; new section "Screenshots,
  recording & trim" with `docs/media/demo-capture.gif`; the `--demo=` footnote
  gains the new scenarios. Raycast bullet links the still.
- `docs/raycast.md`: the still (`docs/media/raycast.png`) under Setup.
- `docs/development.md` + `AGENTS.md`: extended `--demo=` list.

## Error handling

Same posture as existing scenarios: fail fast (`DemoError`) rather than film
a broken take — missing hotbar/card anchors after a timeout, card not visible,
drop bubble not confirmed (the helper window check stays PID-strict), Raycast
window not found. Cleanup restores every touched setting (adds
`hotbarEnabled`), tears down taps/mock windows, terminates the helper.

## Testing

- TDD: `Geometry.demoAnchorRect` conversion (flipped y, panel offset).
- Everything else is runtime-verified footage: record each scenario, extract
  frames with ffmpeg and inspect them for each beat before converting to GIF.
- `swift test` green, zero build warnings, existing scenarios re-run unharmed
  only if their shared plumbing changed (they're untouched otherwise).
