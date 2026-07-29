# Demo Showcase Clips Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Two new self-recorded README clips (`--demo=zoom`, `--demo=capture`), a Raycast still (`--demo=raycast`), a pinned mp4→GIF script, and the README/docs updates that showcase them.

**Architecture:** Extend `DemoDirector` (Sources/OutcutShare/DemoHarness.swift) with three scenarios in the existing choreography style. Hotbar buttons and capture-card chips get on-demand demo anchor lookups (`session.demoHotbarItemRect(_:)`, `session.demoCardItemRect(_:)`) fed by the SwiftUI views' existing/new anchor preferences, converted to screen coordinates through the owning panel's frame. The helper's chat window becomes a real cross-process file-drop target.

**Tech Stack:** Swift 5 / AppKit / SwiftUI, ScreenCaptureKit (existing engines), ffmpeg for GIF conversion.

## Global Constraints

- Zero build warnings; `swift test` green before merging.
- Feature branch `feature/demo-showcase-clips`; merge `--no-ff` to main, push; NEVER cut a release.
- Choreography may only touch the helper process's windows (`helperWindows(in:)`); the sole, deliberate exception is the Raycast scenario (open launcher, type query, Esc — no Enter, no drags).
- Comments state non-obvious constraints only ("why", never the diff).
- Commit messages are user-facing (conventional commits feed the changelog).
- Demo-only code paths must be inert in normal runs (`DemoState.active` guards).
- All new pure math lives in `Geometry.swift`, TDD'd.
- The user's release-app instance may be running — never kill or touch it.

---

### Task 1: `Geometry.demoAnchorScreenRect` (TDD)

**Files:**
- Modify: `Sources/OutcutShare/Geometry.swift` (near `demoStageRect`, ~line 436)
- Test: `Tests/OutcutShareTests/GeometryTests.swift` (append)

**Interfaces:**
- Produces: `static func demoAnchorScreenRect(local: CGRect, panelFrame: CGRect) -> CGRect` — SwiftUI-global rect (top-left origin, hosting view fills a borderless panel) → AppKit screen rect.

- [ ] **Step 1: Write the failing test**

```swift
func testDemoAnchorScreenRectFlipsWithinPanel() {
    let panel = CGRect(x: 100, y: 50, width: 300, height: 60)
    let local = CGRect(x: 10, y: 5, width: 30, height: 30) // 5pt below panel top
    let screen = Geometry.demoAnchorScreenRect(local: local, panelFrame: panel)
    XCTAssertEqual(screen, CGRect(x: 110, y: 75, width: 30, height: 30))
}
```

- [ ] **Step 2: Run** `swift test --filter testDemoAnchorScreenRect` — expect FAIL (no such function).
- [ ] **Step 3: Implement**

```swift
/// A SwiftUI anchor rect (top-left origin inside a borderless panel's
/// hosting view) as an AppKit screen rect — demo choreography clicks these.
static func demoAnchorScreenRect(local: CGRect, panelFrame: CGRect) -> CGRect {
    CGRect(x: panelFrame.minX + local.minX,
           y: panelFrame.maxY - local.maxY,
           width: local.width, height: local.height)
}
```

- [ ] **Step 4: Run** the test — expect PASS.
- [ ] **Step 5: Commit** `feat: demo anchor rect conversion for choreographed clicks`

### Task 2: Hotbar demo anchors

**Files:**
- Modify: `Sources/OutcutShare/Hotbar.swift` (`HotbarActions`, `HotbarView.body`, `HotbarController`)
- Modify: `Sources/OutcutShare/ShareSession.swift` (near `debugToggleFollowMenu`, ~line 257)

**Interfaces:**
- Consumes: `Geometry.demoAnchorScreenRect` (Task 1).
- Produces: `ShareSession.demoHotbarItemRect(_ help: String) -> CGRect?` (AppKit screen rect, on demand — always fresh even after the panel repositions). Keys are the buttons' existing help strings, e.g. `"Screenshot shared region"`, `"Start recording"`, `"Stop recording"`.

- [ ] **Step 1:** Add `var reportItemBounds: ([String: CGRect]) -> Void = { _ in }` to `HotbarActions`. In `HotbarView.body`, extend the existing `.overlayPreferenceValue(BarItemBounds.self)` block: inside the `GeometryReader`, attach to `flyouts(...)`:

```swift
.onChange(of: anchors.mapValues { geo[$0] }, initial: true) { _, rects in
    if DemoState.active { actions.reportItemBounds(rects) }
}
```

- [ ] **Step 2:** In `HotbarController`: store `private var demoLocalAnchors: [String: CGRect] = [:]`, set `reportItemBounds` when building `HotbarActions`, and add:

```swift
/// Demo choreography: a bar button's current screen rect, by help string.
func demoItemRect(_ help: String) -> CGRect? {
    guard let panel, panel.isVisible, let local = demoLocalAnchors[help] else { return nil }
    return Geometry.demoAnchorScreenRect(local: local, panelFrame: panel.frame)
}
```

- [ ] **Step 3:** In `ShareSession`, next to `debugToggleFollowMenu`, add `func demoHotbarItemRect(_ help: String) -> CGRect? { hotbar.demoItemRect(help) }`.
- [ ] **Step 4:** Build (`swift build`) — zero warnings.
- [ ] **Step 5: Commit** `feat: hotbar exposes button rects to demo choreography`

### Task 3: Capture-card demo anchors

**Files:**
- Modify: `Sources/OutcutShare/CaptureResultPreview.swift` (`CaptureResultActions`, `CaptureResultView`, `TrimTimeline` call-site, `CaptureResultController`)
- Modify: `Sources/OutcutShare/ShareSession.swift`

**Interfaces:**
- Consumes: `Geometry.demoAnchorScreenRect`.
- Produces: `ShareSession.demoCardItemRect(_ key: String) -> CGRect?`. Keys: chip help strings (`"Trim recording"`, `"Save trimmed copy"`, `"Copy file — or drag it out"`, …) plus `"__image__"` (drag-out surface) and `"__timeline__"` (trim strip).

- [ ] **Step 1:** Add a `CardItemBounds: PreferenceKey` (same shape as `BarItemBounds`). In `CaptureResultView`: `chip(...)` gains `.anchorPreference(key: CardItemBounds.self, value: .bounds) { [help: $0] }`; the image area (the `.overlay(FileDragArea(...))` group) gains key `"__image__"`; the `TrimTimeline(...)` call-site gains `"__timeline__"`. On the root `VStack`, add:

```swift
.overlayPreferenceValue(CardItemBounds.self) { anchors in
    GeometryReader { geo in
        Color.clear
            .onChange(of: anchors.mapValues { geo[$0] }, initial: true) { _, rects in
                if DemoState.active { actions.reportItemBounds(rects) }
            }
    }
}
```

- [ ] **Step 2:** `CaptureResultActions` gains `var reportItemBounds: ([String: CGRect]) -> Void = { _ in }`; `CaptureResultController` stores the locals and exposes `demoItemRect(_:)` exactly like the hotbar (panel-visible guard + `Geometry.demoAnchorScreenRect`).
- [ ] **Step 3:** `ShareSession`: `func demoCardItemRect(_ key: String) -> CGRect? { resultPreview.demoItemRect(key) }`.
- [ ] **Step 4:** Build; then runtime-check both hook tasks: `.build/debug/OutcutShare --result-card-test=<some png>` still shows the card (hooks inert without demo mode).
- [ ] **Step 5: Commit** `feat: capture card exposes chip and timeline rects to demo choreography`

### Task 4: Chat helper window accepts file drops

**Files:**
- Modify: `Sources/OutcutShare/DemoContent.swift` (`DemoChatView`)

**Interfaces:**
- Produces: dropping a file URL onto the chat helper window appends an image bubble (right-aligned, like "mine" messages). Runs in the helper process — always active there, unreachable in normal app runs.

- [ ] **Step 1:** Give `DemoChatView` `@State private var droppedImage: NSImage?`; render after the last bubble:

```swift
if let image = droppedImage {
    HStack {
        Spacer(minLength: 30)
        Image(nsImage: image)
            .resizable().scaledToFit()
            .frame(maxWidth: 190)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
```

and on the outer `VStack`:

```swift
.dropDestination(for: URL.self) { urls, _ in
    guard let url = urls.first, let image = NSImage(contentsOf: url) else { return false }
    droppedImage = image
    return true
}
```

- [ ] **Step 2:** Build; manual check: run `.build/debug/OutcutShare --demo-windows=100,100,900,500`, drag any image file from Finder onto the Team Chat window, bubble appears. (This one manual drag is the developer verifying, not choreography.) Kill the helper.
- [ ] **Step 3: Commit** `feat: demo chat window shows dropped captures as a bubble`

### Task 5: `--demo=zoom` scenario

**Files:**
- Modify: `Sources/OutcutShare/DemoHarness.swift` (new scenario + switch case + saved settings)
- Modify: `Sources/OutcutShare/AppDelegate.swift:226` (comment listing scenarios)

**Interfaces:**
- Consumes: `session.startSharing(rect:on:)`, `session.toggleZoom()`, `session.sharePreset(_:)`, `DemoMeetMock`, `session.demoFrameTap`, `WindowMover.move(window:toAppKitOrigin:raise:)`.
- Produces: `demo-zoom <date>.mp4` in the Demos folder.

- [ ] **Step 1:** In `DemoDirector`, save/restore `settings.hotbarEnabled` and `settings.zoomFactor` (add `savedHotbarEnabled`/`savedZoomFactor`, restore in `cleanup()`).
- [ ] **Step 2:** Add the scenario (registered as `case "zoom"`), following `regionScenario`'s staging:

```swift
/// Viewer zoom: the call mirror punches into a 2× window that tracks the
/// cursor while the stage visibly stays put; then a preset glides the
/// live region — the share never drops.
private func zoomScenario(screen: NSScreen) async throws -> URL {
    settings.shareMode = .hiddenWindow
    settings.previewWindowEnabled = false
    settings.hotbarEnabled = false // the bar would trail both region hops
    settings.zoomFactor = 2.0
    let callFrame = CGRect(x: stage.maxX - stage.width * 0.40 - 16,
                           y: stage.minY + stage.height * 0.16,
                           width: stage.width * 0.40, height: stage.height * 0.52)
    let meet = DemoMeetMock(frame: callFrame)
    meetMock = meet
    session.demoFrameTap = { [weak meet] surface in meet?.display(surface: surface) }

    // Two 16:9 region slots on the left: notes+metrics fill the TOP one,
    // chat sits in the BOTTOM one (the preset glides down to it).
    let regionW = stage.width * 0.42
    let regionH = regionW * 9 / 16
    let regionTop = CGRect(x: stage.minX + stage.width * 0.035,
                           y: stage.maxY - stage.height * 0.08 - regionH,
                           width: regionW, height: regionH)
    let regionBottom = regionTop.offsetBy(dx: 0, dy: -(regionH + stage.height * 0.06))
    let windows = try helperWindows(in: stage)
    guard windows.count >= 3 else { throw DemoError.missingDemoWindow }
    // Sorted by x so the assignment is deterministic: notes, metrics, chat.
    let sorted = windows.sorted { $0.frame.minX < $1.frame.minX }
    WindowMover.move(window: sorted[0], toAppKitOrigin:
        CGPoint(x: regionTop.minX + 8, y: regionTop.minY - 20), raise: true)
    WindowMover.move(window: sorted[1], toAppKitOrigin:
        CGPoint(x: regionTop.midX + 8, y: regionTop.midY - 40), raise: true)
    WindowMover.move(window: sorted[2], toAppKitOrigin:
        CGPoint(x: regionBottom.minX + regionW * 0.22, y: regionBottom.minY + 8),
        raise: true)
    // Frontmost hygiene: focus a helper window before sharing.
    await driver.click(at: titleBarPoint(of: sorted[0].frame))
    await driver.pause(0.5)

    let url = try startRecording(screen: screen)
    await driver.pause(0.6)
    session.startSharing(rect: regionTop, on: screen)
    try await waitForActive()
    await driver.pause(1.2)

    // Beat 1: zoom in — mirror punches in, stage stays put.
    keystrokeHUD?.show(key: "⌃⌥⌘Z", caption: "Viewers zoom in — your screen stays put")
    await driver.move(to: CGPoint(x: regionTop.midX + regionW * 0.26,
                                  y: regionTop.midY), over: 0.8)
    session.toggleZoom()
    await driver.pause(1.8)

    // Beat 2: the zoom window tracks the cursor.
    keystrokeHUD?.show(key: "Zoom", caption: "Follows your cursor")
    await driver.move(to: CGPoint(x: regionTop.minX + regionW * 0.18,
                                  y: regionTop.maxY - regionH * 0.30), over: 1.6)
    await driver.pause(0.8)
    await driver.move(to: CGPoint(x: regionTop.minX + regionW * 0.20,
                                  y: regionTop.minY + regionH * 0.25), over: 1.4)
    await driver.pause(0.9)

    // Beat 3: zoom back out.
    session.toggleZoom()
    await driver.pause(1.4)

    // Beat 4: live preset switch — the region glides, the share survives.
    keystrokeHUD?.show(key: "⌃⌥⌘1", caption: "Preset — the region glides, the share never stops")
    session.sharePreset(RegionPreset(
        name: "Chat", region: StoredRegion(rect: regionBottom,
                                           displayID: screen.displayID),
        shareModeRaw: ShareMode.hiddenWindow.rawValue))
    await driver.pause(2.4)
    keystrokeHUD?.hide()
    await driver.pause(0.8)
    session.stop()
    await driver.pause(0.8)
    return url
}
```

- [ ] **Step 3:** Build zero-warning; update the `--demo=` comment in AppDelegate.
- [ ] **Step 4:** Record: `make app` then `build/OutcutShare.app/Contents/MacOS/OutcutShare --demo=zoom`. Verify beats by extracting frames (`ffmpeg -i <mp4> -vf fps=2 frames/z%03d.png`) and inspecting: mirror zoomed vs stage unchanged; tracking pan; glide to chat with the "presenting" pill uninterrupted. Iterate constants until it reads.
- [ ] **Step 5: Commit** `feat: viewer zoom + live preset demo scenario (--demo=zoom)`

### Task 6: `--demo=capture` scenario

**Files:**
- Modify: `Sources/OutcutShare/DemoHarness.swift`

**Interfaces:**
- Consumes: `demoHotbarItemRect`, `demoCardItemRect` (Tasks 2–3), chat drop target (Task 4), `session.captureScreenshot`/`toggleRecording` via real hotbar clicks.
- Produces: `demo-capture <date>.mp4`.

- [ ] **Step 1:** Save/restore in `DemoDirector`: `recordSystemAudio` (set false), `recordMicrophone` (set false — a mic prompt would freeze the take), `recentCaptures` (restore), screenshot/recording folder settings (redirect to a scratch dir AFTER `startRecording(screen:)` has begun the stage recording, restore in `cleanup()` — the card's files must not land in the user's folders):

```swift
/// The scenario's screenshots/recordings go to a scratch dir the user never
/// sees. Called after the STAGE recording started (that one still belongs
/// in Demos). Exact SettingsStore keys: whatever backs
/// screenshotFolderURL/recordingFolderURL (folder-path strings — discover
/// and save/restore both alongside recentCaptures).
private func redirectCaptureFolders() {
    let scratch = FileManager.default.temporaryDirectory
        .appendingPathComponent("OutcutShareDemo", isDirectory: true).path
    savedScreenshotFolder = settings.screenshotFolder
    savedRecordingFolder = settings.recordingFolder
    savedRecentCaptures = settings.recentCaptures
    settings.screenshotFolder = scratch
    settings.recordingFolder = scratch
}
```
- [ ] **Step 2:** Add `case "capture"`:

```swift
/// The capture workflow, driven through the real hotbar: screenshot →
/// card → drag the file into a chat, then record → trim on the card.
private func captureScenario(screen: NSScreen) async throws -> URL {
    settings.shareMode = .hiddenWindow
    settings.previewWindowEnabled = false
    settings.hotbarEnabled = true
    let region = CGRect(x: stage.minX + stage.width * 0.04,
                        y: stage.minY + stage.height * 0.42,
                        width: stage.width * 0.42, height: stage.height * 0.50)
    let chatFrame = CGRect(x: stage.minX + stage.width * 0.52,
                           y: stage.minY + stage.height * 0.10,
                           width: stage.width * 0.21, height: stage.height * 0.36)
    let sorted = try helperWindows(in: stage).sorted { $0.frame.minX < $1.frame.minX }
    guard sorted.count >= 3 else { throw DemoError.missingDemoWindow }
    WindowMover.move(window: sorted[0], toAppKitOrigin:
        CGPoint(x: region.minX + 10, y: region.minY + 10), raise: true)
    WindowMover.move(window: sorted[1], toAppKitOrigin:
        CGPoint(x: region.midX, y: region.midY - 30), raise: true)
    WindowMover.move(window: sorted[2], toAppKitOrigin: chatFrame.origin, raise: true)
    await driver.click(at: titleBarPoint(of: sorted[0].frame))
    await driver.pause(0.4)

    let url = try startRecording(screen: screen)
    redirectCaptureFolders() // scratch dir; restored in cleanup()
    await driver.pause(0.6)
    session.startSharing(rect: region, on: screen)
    try await waitForActive()
    await driver.pause(1.4) // hotbar settles under the region

    // Beat 1: screenshot from the hotbar; the card folds out beneath it.
    keystrokeHUD?.show(key: "Screenshot", caption: "One click on the hotbar")
    guard let camera = session.demoHotbarItemRect("Screenshot shared region") else {
        throw DemoError.missingDemoWindow
    }
    await driver.click(at: CGPoint(x: camera.midX, y: camera.midY))
    let image = try await waitForCardItem("__image__")
    await driver.move(to: CGPoint(x: image.midX, y: image.midY), over: 0.5)
    await driver.pause(0.8)

    // Beat 2: drag the file out of the card, into the chat.
    keystrokeHUD?.show(key: "Drag", caption: "The file goes anywhere — chat, mail, Finder")
    guard let chat = try helperWindows(in: chatFrame.insetBy(dx: -20, dy: -20)).first else {
        throw DemoError.missingDemoWindow
    }
    await driver.drag(from: CGPoint(x: image.midX, y: image.midY),
                      to: CGPoint(x: chat.frame.midX, y: chat.frame.midY - 30),
                      over: 1.5)
    await driver.pause(1.2) // bubble lands, card countdown resumes

    // Beat 3: record the region.
    keystrokeHUD?.show(key: "Record", caption: "The region straight to .mp4")
    guard let record = session.demoHotbarItemRect("Start recording") else {
        throw DemoError.missingDemoWindow
    }
    await driver.click(at: CGPoint(x: record.midX, y: record.midY))
    // Motion for the filmstrip: glide across the notes, nudge a window.
    await driver.move(to: CGPoint(x: region.minX + region.width * 0.25,
                                  y: region.midY), over: 1.0)
    await driver.drag(from: titleBarPoint(of: sorted[1].frame),
                      to: CGPoint(x: region.midX + 30, y: region.midY + 10),
                      over: 1.2)
    await driver.pause(0.8)
    guard let stop = session.demoHotbarItemRect("Stop recording") else {
        throw DemoError.missingDemoWindow
    }
    await driver.click(at: CGPoint(x: stop.midX, y: stop.midY))
    let video = try await waitForCardItem("__image__")
    await driver.move(to: CGPoint(x: video.midX, y: video.midY), over: 0.5)

    // Beat 4: trim right on the card — scrub preview under the handles.
    keystrokeHUD?.show(key: "Trim", caption: "Cut it right on the card")
    guard let scissors = session.demoCardItemRect("Trim recording") else {
        throw DemoError.missingDemoWindow
    }
    await driver.click(at: CGPoint(x: scissors.midX, y: scissors.midY))
    await driver.pause(1.0) // card grows, filmstrip loads
    guard let strip = session.demoCardItemRect("__timeline__") else {
        throw DemoError.missingDemoWindow
    }
    // The strip's gesture grabs the nearer handle: right end → out handle.
    await driver.move(to: CGPoint(x: strip.maxX - 4, y: strip.midY), over: 0.6)
    await driver.press(at: CGPoint(x: strip.maxX - 4, y: strip.midY))
    await driver.move(to: CGPoint(x: strip.minX + strip.width * 0.62, y: strip.midY),
                      over: 1.2, dragging: true)
    await driver.release(at: CGPoint(x: strip.minX + strip.width * 0.62, y: strip.midY))
    await driver.pause(0.5)
    await driver.press(at: CGPoint(x: strip.minX + 4, y: strip.midY))
    await driver.move(to: CGPoint(x: strip.minX + strip.width * 0.18, y: strip.midY),
                      over: 0.9, dragging: true)
    await driver.release(at: CGPoint(x: strip.minX + strip.width * 0.18, y: strip.midY))
    await driver.pause(0.4)
    guard let save = session.demoCardItemRect("Save trimmed copy") else {
        throw DemoError.missingDemoWindow
    }
    await driver.click(at: CGPoint(x: save.midX, y: save.midY))
    await driver.pause(1.6) // export → pop → card back to normal size
    keystrokeHUD?.hide()
    // Step clear so the countdown runs out on film.
    await driver.move(to: CGPoint(x: stage.minX + 60, y: stage.minY + 60), over: 0.6)
    await driver.pause(1.2)
    session.stop()
    await driver.pause(0.6)
    return url
}

/// Polls a card anchor until the card is up and settled.
private func waitForCardItem(_ key: String) async throws -> CGRect {
    var last: CGRect?
    for _ in 0..<60 {
        try await Task.sleep(nanoseconds: 100_000_000)
        if let rect = session.demoCardItemRect(key) {
            if let l = last, l == rect { return rect } // two stable reads
            last = rect
        }
    }
    throw DemoError.missingDemoWindow
}
```

- [ ] **Step 3:** Build; record `--demo=capture` from the app bundle binary; extract frames and verify every beat (card visible, bubble landed, red record state, filmstrip + dimmed cut ranges + scrub image, normal card after save). Iterate.
- [ ] **Step 4:** Playback speed: add `"capture"` to the retimer choice (1.5 like region/follow; adjust after viewing).
- [ ] **Step 5: Commit** `feat: capture workflow demo scenario (--demo=capture)`

### Task 7: `--demo=raycast` still

**Files:**
- Modify: `Sources/OutcutShare/DemoHarness.swift` (`runScenario` branches: raycast skips helper + session recording; backdrop still shown so Raycast's vibrancy blurs our wallpaper, not the desktop)

**Interfaces:**
- Produces: `demo-raycast <date>.png` in the Demos folder.

- [ ] **Step 1:** Branch in `runScenario` before `launchHelper()`: for `"raycast"`, show backdrop, skip helper/countdown recording, run:

```swift
private func raycastScenario() async throws -> URL {
    NSWorkspace.shared.open(URL(string: "raycast://")!) // opens root search
    await driver.pause(1.4)
    await typeString("outcut share")
    await driver.pause(1.6)
    guard let windowID = frontmostWindowID(ownerName: "Raycast") else {
        throw DemoError.missingDemoWindow
    }
    let dir = settings.recordingFolderURL.appendingPathComponent("Demos")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("demo-raycast.png")
    let capture = Process()
    capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    capture.arguments = ["-x", "-o", "-l", String(windowID), url.path]
    try capture.run()
    capture.waitUntilExit()
    await driver.tapKey(53) // Esc — leave Raycast as found
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw DemoError.missingDemoWindow
    }
    return url
}

/// Layout-independent typing (German QWERTZ in play): the characters ride
/// on the event, not on virtual key codes.
private func typeString(_ text: String) async {
    for unit in Array(text.utf16) {
        var chars = [unit]
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: 0,
                                keyDown: keyDown)
            event?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &chars)
            event?.post(tap: .cghidEventTap)
        }
        await driver.pause(0.05)
    }
}

private func frontmostWindowID(ownerName: String) -> CGWindowID? {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
        as? [[String: Any]] ?? []
    return list.first {
        $0[kCGWindowOwnerName as String] as? String == ownerName
            && ($0[kCGWindowBounds as String] as? [String: CGFloat])?["Width"] ?? 0 > 300
    }.flatMap { $0[kCGWindowNumber as String] as? CGWindowID }
}
```

- [ ] **Step 2:** Precondition check before recording: the extension must be imported (Raycast dev mode). If the PNG shows no Outcut Share commands, run `cd raycast && npm install && npm run dev` (background), wait for import, kill it, re-capture.
- [ ] **Step 3:** Run, Read the PNG, verify the command list renders (English UI, no personal results beyond the app itself). Iterate on pauses if the query hadn't finished rendering.
- [ ] **Step 4: Commit** `feat: raycast command-list still (--demo=raycast)`

### Task 8: GIF script + convert

**Files:**
- Create: `Scripts/demo-gif.sh` (chmod +x)

- [ ] **Step 1:**

```sh
#!/bin/sh
# Demo mp4 → README GIF with the parameters the existing clips use.
set -e
[ $# -eq 2 ] || { echo "usage: demo-gif.sh in.mp4 out.gif" >&2; exit 2; }
ffmpeg -y -i "$1" -vf "fps=12.5,scale=900:-2:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4" "$2"
```

- [ ] **Step 2:** Convert both keeper takes to `docs/media/demo-zoom.gif` and `docs/media/demo-capture.gif`; copy the still to `docs/media/raycast.png`. Sanity: GIF sizes in the 2–5 MB band of the existing clips.
- [ ] **Step 3: Commit** `feat: demo gif conversion script` (script only; media lands with Task 9)

### Task 9: README + docs

**Files:**
- Modify: `README.md`, `docs/development.md`, `docs/raycast.md`, `AGENTS.md`
- Add: `docs/media/demo-zoom.gif`, `docs/media/demo-capture.gif`, `docs/media/raycast.png`

- [ ] **Step 1:** README: insert section **"Viewer zoom & live presets"** after Region selection (GIF + 3–4 lines: ⌃⌥⌘Z zoom glides toward the cursor and tracks it, viewers only; presets glide the live region, share never drops). Insert **"Screenshots, recording & trim"** after Follow mode (GIF + lines: hotbar camera/record, preview card, drag the file out, drag-to-trim with scrub). Update the recording footnote to `--demo=region|zoom|capture|follow|monitor` (raycast still mentioned in development.md). Add the still to the Raycast bullet in "What else it can do" only if it reads well — else docs-only.
- [ ] **Step 2:** `docs/raycast.md`: image under Setup. `docs/development.md`: extend the demo block with `zoom`, `capture`, `raycast` (still). `AGENTS.md` debug-flags block: same.
- [ ] **Step 3:** Proof-read rendered README (`grep`-check image paths exist).
- [ ] **Step 4: Commit** `docs: showcase viewer zoom and capture workflow clips, raycast still`

### Task 10: Verify, merge, relaunch

- [ ] **Step 1:** `swift test` green; `make app` zero warnings.
- [ ] **Step 2:** Re-run one legacy scenario touched by shared plumbing only if shared code changed (`--demo=region` spot-check) — otherwise skip.
- [ ] **Step 3:** `git checkout main && git merge --no-ff feature/demo-showcase-clips && git push`.
- [ ] **Step 4:** `make app && pkill -x OutcutShare; open build/OutcutShare.app`.
- [ ] **Step 5:** Mark tasks complete.
