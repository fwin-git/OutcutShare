# Presenter zoom + recording audio — design

Date: 2026-07-29. Both features picked by the user from the feature
proposal ("implement 1 (hotkey), softly/smoothly animated & not jarring
+ 2 (mic + system audio)").

## 1. Presenter zoom (viewers-only punch-in)

A hotkey (default ⌃⌥⌘Z, rebindable like every other action) toggles a
zoom of the *shared picture* toward the cursor. The presenter's screen —
region, dim, overlays — never changes; only the capture `sourceRect`
shrinks, so the fixed output scales up = zoom. Works in both region
modes (hidden window & virtual display); recordings, screenshots and the
shared-output preview see the zoomed picture automatically because they
all consume the same stream. Not available in Virtual Monitor mode.

- **ZoomController** (new, mirrors FollowController): 60 Hz timer glides
  the capture window exponentially toward its target (soft ease, no
  jumps). Enter: target = region/factor rect centered on the cursor,
  clamped inside the region. While zoomed: the window tracks the cursor
  with a dead-zone shift (same `Geometry.deadZoneShift` mechanic as
  cursor follow) — only while the cursor is inside the region. Exit:
  glides back to the full region, then the timer stops.
- **Geometry.zoomWindow(region:focus:factor:)** — pure, TDD'd: the
  region/factor sub-rect centered on focus, clamped inside the region;
  factor ≤ 1 returns the region.
- **ShareSession**: `toggleZoom()` (guards active + not monitor),
  `isZoomedIn`, and an `applyZoomWindow(_:)` path that feeds the existing
  coalesced `scheduleCaptureUpdate` with pixelSize nil (output size
  untouched). The zoom cancels (state reset, no extra capture update)
  whenever the region rect changes — move/resize/follow re-point the
  stream to the full region anyway — and on teardown.
- **Setting**: `zoomFactor` (Double, default 2.0; General page picker
  1.5× / 2× / 3×).
- **Menu bar**: a "Zoom In (Viewers)" / "Zoom Out (Viewers)" item next to
  Move/Resize, enabled while a region session is active.
- **Harness**: `--zoom-at=t1,t2` share-test companion; E2E compares
  screenshots taken before/while zoomed.

## 2. Recording audio (system + microphone)

Two new *Settings → Recording* toggles: **Record system audio** (default
on) and **Record microphone** (default off). Recordings become .mp4 with
up to two AAC audio tracks (48 kHz stereo, 160 kbit/s); privacy pause
gates audio exactly like video — nothing is written while paused.

- **System audio**: `SCStreamConfiguration.capturesAudio` is always on
  with `excludesCurrentProcessAudio`; CaptureEngine adds an `.audio`
  stream output and exposes `onAudioSampleBuffer`. ShareSession connects
  it to the recorder only while recording with the toggle on.
- **Microphone**: new `MicCapture` (AVCaptureSession + audio data output
  on its own queue). Started per recording when the toggle is on;
  `NSMicrophoneUsageDescription` added to Info.plist. Permission flow:
  not-determined → system prompt on first mic recording (mic joins the
  file once granted); denied → an alert explains it and the recording
  continues without mic.
- **RecordingEngine**: `start(...)` gains `systemAudio:`/`microphone:`;
  audio inputs transcode to AAC; audio buffers are dropped until the
  writer session has started (it anchors on the first video frame).

## Out of scope

Zoom via URL scheme/Raycast/hotbar, zoom combined with an actively
moving region (follow) — zoom simply ends when the region moves. Audio
mixing into a single track (two tracks; players play both), input level
metering, device pickers (system default mic only).
