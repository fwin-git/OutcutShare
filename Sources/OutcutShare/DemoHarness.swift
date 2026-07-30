import AppKit
import CoreGraphics
import CoreMedia

/// Demo-mode toggles read by the normal pipeline.
@MainActor
enum DemoState {
    /// Session captures keep the helper process visible (PID-only own-app
    /// exclusion instead of PID + bundle id — the helper shares our bundle).
    static var active = false
    /// The layout grid reads hardware modifier state, which synthetic
    /// events can't set — the choreography forces it here instead.
    static var gridModifierForced = false
}

/// Synthesizes smooth, human-looking mouse input (the process must hold the
/// Accessibility permission — run the demo via the granted app bundle's
/// binary).
@MainActor
final class DemoDriver {
    /// Global pacing: every scripted pause is shortened for a snappy cut.
    private static let pauseScale = 0.775

    private var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    private func post(_ type: CGEventType, at appKit: CGPoint,
                      button: CGMouseButton = .left, flags: CGEventFlags = []) {
        let point = Geometry.cgPoint(fromAppKit: appKit, primaryHeight: primaryHeight)
        guard let event = CGEvent(mouseEventSource: nil, mouseType: type,
                                  mouseCursorPosition: point, mouseButton: button) else {
            return
        }
        event.flags = flags
        event.post(tap: .cghidEventTap)
    }

    func pause(_ seconds: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * Self.pauseScale
                                                  * 1_000_000_000))
    }

    /// Eased cursor glide, ~60 Hz. `flags` ride on every event — the
    /// selector and other overlays read per-event modifiers, so synthetic
    /// ⇧/⌃ work exactly like held keys.
    func move(to target: CGPoint, over duration: TimeInterval,
              dragging: Bool = false, flags: CGEventFlags = []) async {
        let start = NSEvent.mouseLocation
        let steps = max(2, Int(duration * 60))
        for i in 1...steps {
            let t = Double(i) / Double(steps)
            let eased = t * t * (3 - 2 * t) // smoothstep
            let p = CGPoint(x: start.x + (target.x - start.x) * eased,
                            y: start.y + (target.y - start.y) * eased)
            post(dragging ? .leftMouseDragged : .mouseMoved, at: p, flags: flags)
            try? await Task.sleep(nanoseconds: UInt64(duration / Double(steps)
                                                      * 1_000_000_000))
        }
    }

    func press(at p: CGPoint, flags: CGEventFlags = []) async {
        post(.leftMouseDown, at: p, flags: flags)
        await pause(0.08)
    }

    func release(at p: CGPoint, flags: CGEventFlags = []) async {
        post(.leftMouseUp, at: p, flags: flags)
        await pause(0.15)
    }

    func click(at p: CGPoint) async {
        await move(to: p, over: 0.4)
        await press(at: p)
        await release(at: p)
    }

    /// Key tap (e.g. Space = 49) delivered to the focused window.
    func tapKey(_ keyCode: CGKeyCode) async {
        if let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode,
                              keyDown: true) {
            down.post(tap: .cghidEventTap)
        }
        await pause(0.08)
        if let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode,
                            keyDown: false) {
            up.post(tap: .cghidEventTap)
        }
        await pause(0.1)
    }

    /// A full grab-move-drop of whatever is under `from`.
    func drag(from: CGPoint, to: CGPoint, over duration: TimeInterval) async {
        await move(to: from, over: 0.6)
        await press(at: from)
        await move(to: to, over: duration, dragging: true)
        await release(at: to)
    }
}

/// Compresses presentation timestamps so the finished file plays back
/// sped up (all frames kept — just closer together). Called from the
/// capture sample queue, which is serial.
final class SampleRetimer: @unchecked Sendable {
    private let speed: Double
    private var anchor: CMTime?

    init(speed: Double) {
        self.speed = speed
    }

    func retimed(_ sample: CMSampleBuffer) -> CMSampleBuffer {
        let pts = CMSampleBufferGetPresentationTimeStamp(sample)
        if anchor == nil {
            anchor = pts
        }
        guard let anchor else { return sample }
        let scaled = CMTimeMultiplyByFloat64(CMTimeSubtract(pts, anchor),
                                             multiplier: 1.0 / speed)
        var timing = CMSampleTimingInfo(duration: CMSampleBufferGetDuration(sample),
                                        presentationTimeStamp: CMTimeAdd(anchor, scaled),
                                        decodeTimeStamp: .invalid)
        var out: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault,
                                              sampleBuffer: sample,
                                              sampleTimingEntryCount: 1,
                                              sampleTimingArray: &timing,
                                              sampleBufferOut: &out)
        return out ?? sample
    }
}

/// Screencast-style keystroke indicator: a chip at the stage's bottom
/// center whenever the choreography holds a key, so viewers can follow the
/// modifier-driven interactions.
@MainActor
final class DemoKeystrokeHUD {
    private let stage: CGRect
    private var panel: NSPanel?

    init(stage: CGRect) {
        self.stage = stage
    }

    func show(_ label: String) {
        show(key: label, caption: nil)
    }

    /// Key chip with an optional explanation, sliding in so each modifier
    /// beat reads as its own interaction. White chip, dark text — a black
    /// chip drowned in the dark wallpaper.
    func show(key: String, caption: String?) {
        hide()
        // Big glyphs for single keys, readable size for text labels.
        let keyFont = NSFont.systemFont(ofSize: key.count > 2 ? 30 : 44, weight: .bold)
        let text = NSMutableAttributedString(
            string: key,
            attributes: [.font: keyFont,
                         .foregroundColor: NSColor.black.withAlphaComponent(0.88)])
        if let caption {
            text.append(NSAttributedString(
                string: "   \(caption)",
                attributes: [.font: NSFont.systemFont(ofSize: 21, weight: .semibold),
                             .foregroundColor: NSColor.black.withAlphaComponent(0.62)]))
        }
        let textSize = text.size()
        let frame = CGRect(x: stage.midX - (textSize.width + 76) / 2,
                           y: stage.minY + 24,
                           width: textSize.width + 76, height: textSize.height + 34)
        let panel = NSPanel(contentRect: frame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        let view = NSView(frame: CGRect(origin: .zero, size: frame.size))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.92).cgColor
        view.layer?.cornerRadius = 18
        // CATextLayer, not NSTextField: label fields wrapped at the exact
        // measured width and clipped the text ("⇧ Shift" → "⇧").
        let textLayer = CATextLayer()
        textLayer.string = text
        textLayer.alignmentMode = .center
        textLayer.contentsScale = 2
        textLayer.frame = CGRect(x: 0, y: (frame.height - textSize.height) / 2 - 2,
                                 width: frame.width, height: textSize.height + 4)
        view.layer?.addSublayer(textLayer)
        panel.contentView = view
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
        // Slide up + fade in.
        panel.alphaValue = 0
        panel.setFrame(frame.offsetBy(dx: 0, dy: -14), display: false)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(frame, display: true)
        }
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}

/// `--demo=<scenario>` — sets a clean 16:9 stage on the main screen, spawns
/// the helper's fake windows, choreographs real interactions with synthetic
/// input and records the stage to an .mp4. Scenarios: `monitor`, `region`,
/// `follow`, `zoom`, `capture` — plus `raycast`, a still of the Raycast
/// command list.
@MainActor
final class DemoDirector {
    private let session: ShareSession
    private let scenario: String
    private let settings = SettingsStore.shared
    private let driver = DemoDriver()
    private let recorder = RecordingEngine()
    private let capture = CaptureEngine()
    private var helper: Process?
    private var backdrop: NSWindow?
    private var keystrokeHUD: DemoKeystrokeHUD?
    private var stage: CGRect = .zero
    private var savedMode: ShareMode = .virtualDisplay
    private var savedPreview = false
    private var savedFollowBehavior: FollowBehavior = .glide
    private var savedFollowResizes = true
    private var savedHotbarEnabled = true
    private var savedZoomFactor = 2.0
    private var savedRecordSystemAudio = false
    private var savedRecordMicrophone = false
    private var savedPauseStyle: PauseStyle = .privacyScreen
    private var savedPauseMessage = ""
    private var savedPauseImagePath = ""
    /// Set only when the capture scenario redirects the capture folders to
    /// a scratch dir — nil means nothing to restore.
    private var savedCaptureFolders: (screenshot: String, recording: String,
                                      recents: [String])?
    private var meetMock: DemoMeetMock?

    init(session: ShareSession, scenario: String) {
        self.session = session
        self.scenario = scenario
    }

    func run() {
        Task { @MainActor in
            do {
                let url = try await runScenario()
                print("DEMO OK \(url.path)")
                await cleanup()
                exit(0)
            } catch {
                print("DEMO FAIL \(error)")
                await cleanup()
                exit(1)
            }
        }
    }

    enum DemoError: Error {
        case permissionsMissing, helperTimeout, sessionTimeout, unknownScenario
        case missingDemoWindow
    }

    /// ONLY the helper's fake windows may ever be touched — grabbing
    /// whatever CGWindowList finds in the stage once dragged the user's
    /// real windows around. Fail fast instead.
    private func helperWindows(in rect: CGRect) throws -> [WindowLocator.FoundWindow] {
        guard let helperPID = helper?.processIdentifier else {
            throw DemoError.missingDemoWindow
        }
        return WindowLocator.windows(in: rect, excludingPID: getpid())
            .filter { $0.pid == helperPID }
    }

    private func runScenario() async throws -> URL {
        guard CGPreflightScreenCaptureAccess(), WindowMover.hasPermission else {
            print("Grant Screen Recording AND Accessibility to this binary — "
                + "run the release bundle: build/OutcutShare.app/Contents/MacOS/OutcutShare")
            throw DemoError.permissionsMissing
        }
        guard let screen = NSScreen.screens.first else { throw DemoError.sessionTimeout }
        DemoState.active = true
        savedMode = settings.shareMode
        savedPreview = settings.previewWindowEnabled
        savedFollowBehavior = settings.followBehavior
        savedFollowResizes = settings.followResizes
        savedHotbarEnabled = settings.hotbarEnabled
        savedZoomFactor = settings.zoomFactor
        savedRecordSystemAudio = settings.recordSystemAudio
        savedRecordMicrophone = settings.recordMicrophone
        savedPauseStyle = settings.pauseStyle
        savedPauseMessage = settings.pauseMessage
        savedPauseImagePath = settings.pauseImagePath
        stage = Geometry.demoStageRect(visibleFrame: screen.visibleFrame)
        keystrokeHUD = DemoKeystrokeHUD(stage: stage)
        showBackdrop()
        if scenario == "raycast" {
            // A still, not a video: no helper, no stage recording. The
            // backdrop still shields the desktop behind Raycast's vibrancy.
            print("DEMO raycast still in 2s — hands off keyboard (Ctrl-C aborts)")
            await driver.pause(2.0)
            return try await raycastScenario()
        }
        try await launchHelper()
        print("DEMO starting in 3s — hands off mouse & keyboard (Ctrl-C aborts)")
        await driver.pause(3.0)

        let url: URL
        switch scenario {
        case "monitor":
            url = try await monitorScenario(screen: screen)
        case "region":
            url = try await regionScenario(screen: screen)
        case "follow":
            url = try await followScenario(screen: screen)
        case "zoom":
            url = try await zoomScenario(screen: screen)
        case "capture":
            url = try await captureScenario(screen: screen)
        case "pause":
            url = try await pauseScenario(screen: screen)
        default:
            throw DemoError.unknownScenario
        }

        await driver.pause(0.8)
        capture.onSampleBuffer = nil
        await capture.stop()
        _ = await recorder.stop()
        return url
    }

    // MARK: Scenarios

    private func monitorScenario(screen: NSScreen) async throws -> URL {
        settings.shareMode = .virtualMonitor
        session.startSelection()
        try await waitForActive()
        // Compose the scene BEFORE recording: panel onto the stage's right
        // side (16:9, like the monitor), and a click on a fake window so the
        // frontmost app — mirrored into the monitor's menu bar — is ours,
        // not whatever the user last used.
        let panelW = (stage.width * 0.46).rounded()
        let panel = CGRect(x: stage.maxX - panelW - stage.width * 0.04,
                           y: stage.midY - panelW * 9 / 32,
                           width: panelW, height: panelW * 9 / 16)
        session.demoPositionPreview(frame: panel)
        if let front = try helperWindows(in: stage).first {
            let p = titleBarPoint(of: front.frame)
            await driver.move(to: p, over: 0.4)
            await driver.press(at: p)
            await driver.release(at: p)
        }
        await driver.move(to: CGPoint(x: stage.minX + 60, y: stage.minY + 60), over: 0.35)
        await driver.pause(0.4)
        let url = try startRecording(screen: screen)
        await driver.pause(0.7)

        // Drag two fake app windows onto the monitor. Each drop is verified
        // — if the interactive drop ever hiccups, the window is placed
        // directly so the footage never shows a stray.
        guard let notes = try helperWindows(in: stage).first else {
            throw DemoError.missingDemoWindow
        }
        await driver.drag(from: titleBarPoint(of: notes.frame),
                          to: CGPoint(x: panel.minX + panel.width * 0.30,
                                      y: panel.minY + panel.height * 0.62),
                          over: 1.2)
        await driver.pause(0.9)
        try ensureLanded(notes.id, panelPoint: CGPoint(x: panel.minX + panel.width * 0.30,
                                                       y: panel.minY + panel.height * 0.62),
                         panel: panel)
        guard let second = try helperWindows(in: stage).first else {
            throw DemoError.missingDemoWindow
        }
        await driver.drag(from: titleBarPoint(of: second.frame),
                          to: CGPoint(x: panel.minX + panel.width * 0.62,
                                      y: panel.minY + panel.height * 0.52),
                          over: 1.3)
        await driver.pause(0.9)
        try ensureLanded(second.id, panelPoint: CGPoint(x: panel.minX + panel.width * 0.62,
                                                        y: panel.minY + panel.height * 0.52),
                         panel: panel)

        // Grid layout: grab a window inside the preview, sweep a block.
        guard let displayFrame = session.currentRegionRect else { return url }
        let onMonitor = try helperWindows(in: displayFrame)
        if let target = onMonitor.first {
            let grab = panelPoint(forDisplayPoint:
                CGPoint(x: target.frame.midX, y: target.frame.maxY - 14),
                display: displayFrame, panel: panel)
            await driver.move(to: grab, over: 0.5)
            await driver.press(at: grab)
            await driver.move(to: cellCenter(panel, col: 0, row: 1), over: 0.7,
                              dragging: true)
            DemoState.gridModifierForced = true
            keystrokeHUD?.show(settings.dragOutModifier.symbol)
            await driver.move(to: cellCenter(panel, col: 0, row: 1), over: 0.35,
                              dragging: true)
            await driver.move(to: cellCenter(panel, col: 0, row: 0), over: 0.6,
                              dragging: true)
            await driver.release(at: cellCenter(panel, col: 0, row: 0))
            DemoState.gridModifierForced = false
            keystrokeHUD?.hide()
            await driver.pause(0.7)
        }

        // Pull a window back out: ghost rides the cursor off the panel.
        let afterGrid = try helperWindows(in: displayFrame)
        if let target = afterGrid.last {
            let grab = panelPoint(forDisplayPoint:
                CGPoint(x: target.frame.midX, y: target.frame.maxY - 14),
                display: displayFrame, panel: panel)
            await driver.drag(from: grab,
                              to: CGPoint(x: stage.minX + stage.width * 0.24,
                                          y: stage.minY + stage.height * 0.30),
                              over: 1.4)
            await driver.pause(0.9)
        }

        session.stop() // remaining windows return automatically
        await driver.pause(1.5)
        return url
    }

    /// Region sharing showcase: selection with ALL modifier modes (Space
    /// window-pick, ⇧ aspect lock, ⌃ standard sizes), then a mock Meet-style
    /// call mirrors exactly what viewers see while the region moves live.
    private func regionScenario(screen: NSScreen) async throws -> URL {
        settings.shareMode = .hiddenWindow
        settings.previewWindowEnabled = false // the call mock is the mirror
        let callFrame = CGRect(x: stage.maxX - stage.width * 0.40 - 16,
                               y: stage.minY + stage.height * 0.16,
                               width: stage.width * 0.40, height: stage.height * 0.52)
        let meet = DemoMeetMock(frame: callFrame)
        meetMock = meet
        session.demoFrameTap = { [weak meet] surface in
            meet?.display(surface: surface)
        }
        let url = try startRecording(screen: screen)
        // The call mock mirrors the LIVE selection the whole time: crop of
        // the stage capture while dragging, the true share feed once active.
        capture.onFrame = { [weak meet] surface in
            meet?.display(surface: surface)
        }
        RegionSelector.demoSelectionObserver = { [weak self] rect in
            guard let self, let meet = self.meetMock else { return }
            meet.setCrop(Geometry.unitCropRect(of: rect.intersection(self.stage),
                                               in: self.stage))
        }
        await driver.pause(0.6)
        session.startSelection()
        await driver.pause(0.5)

        // The selection modes, one deliberate beat each — a sliding caption
        // chip introduces every mode before its effect plays.
        let origin = CGPoint(x: stage.minX + stage.width * 0.04,
                             y: stage.minY + stage.height * 0.10)

        // Beat 1: freeform drag.
        keystrokeHUD?.show(key: "Drag", caption: "Freeform selection")
        await driver.move(to: origin, over: 0.5)
        await driver.press(at: origin)
        await driver.move(to: CGPoint(x: origin.x + stage.width * 0.22,
                                      y: origin.y + stage.height * 0.40),
                          over: 1.1, dragging: true)
        await driver.pause(0.8)

        // Beat 2: ⌃ snaps to standard screen sizes — settle on one.
        keystrokeHUD?.show(key: "⌃", caption: "Standard screen sizes")
        await driver.pause(0.7)
        await driver.move(to: CGPoint(x: origin.x + stage.width * 0.36,
                                      y: origin.y + stage.height * 0.52),
                          over: 1.5, dragging: true, flags: .maskControl)
        await driver.pause(1.0)

        // Beat 3: back to freeform — any size, any shape.
        keystrokeHUD?.show(key: "Drag", caption: "Back to freeform")
        await driver.pause(0.6)
        await driver.move(to: CGPoint(x: origin.x + stage.width * 0.30,
                                      y: origin.y + stage.height * 0.62),
                          over: 1.0, dragging: true)
        await driver.pause(0.7)

        // Beat 4: ⇧ locks the current aspect ratio.
        keystrokeHUD?.show(key: "⇧", caption: "Locked aspect ratio")
        await driver.pause(0.7)
        await driver.move(to: CGPoint(x: origin.x + stage.width * 0.42,
                                      y: origin.y + stage.height * 0.74),
                          over: 1.3, dragging: true, flags: .maskShift)
        await driver.pause(0.8)

        // Beat 5: holding Space moves the selection as-is.
        keystrokeHUD?.show(key: "Space", caption: "Hold to move the selection")
        await driver.pause(0.7)
        if let down = CGEvent(keyboardEventSource: nil, virtualKey: 49, keyDown: true) {
            down.post(tap: .cghidEventTap)
        }
        await driver.move(to: CGPoint(x: origin.x + stage.width * 0.30,
                                      y: origin.y + stage.height * 0.60),
                          over: 1.1, dragging: true)
        if let up = CGEvent(keyboardEventSource: nil, virtualKey: 49, keyDown: false) {
            up.post(tap: .cghidEventTap)
        }
        await driver.pause(0.8)

        // Finale: Esc this selection, then Space toggles whole-window
        // selection — pick a window and the call mirrors it for real.
        keystrokeHUD?.hide()
        await driver.tapKey(53) // Esc cancels the overlay mid-drag
        await driver.release(at: NSEvent.mouseLocation) // lands on the shield
        await driver.pause(0.5)
        session.startSelection()
        await driver.pause(0.4)
        keystrokeHUD?.show(key: "Space", caption: "Toggle window selection")
        await driver.pause(0.7)
        await driver.tapKey(49)
        guard let pick = try helperWindows(in: stage)
            .first(where: { $0.frame.midX < stage.midX }) else {
            throw DemoError.missingDemoWindow
        }
        await driver.move(to: CGPoint(x: pick.frame.midX, y: pick.frame.midY),
                          over: 0.9)
        await driver.pause(0.9)
        await driver.press(at: CGPoint(x: pick.frame.midX, y: pick.frame.midY))
        await driver.release(at: CGPoint(x: pick.frame.midX, y: pick.frame.midY))
        keystrokeHUD?.hide()
        try await waitForActive()
        // Switch the mirror to the true share feed.
        RegionSelector.demoSelectionObserver = nil
        capture.onFrame = nil
        meet.setCrop(nil)
        await driver.pause(1.6)
        session.stop()
        await driver.pause(0.8)
        return url
    }

    /// Follow modes: the region tracks the active window (with resize),
    /// then trails the cursor.
    private func followScenario(screen: NSScreen) async throws -> URL {
        settings.shareMode = .hiddenWindow
        settings.previewWindowEnabled = true
        settings.followBehavior = .glide
        settings.followResizes = true
        let url = try startRecording(screen: screen)
        await driver.pause(0.5)
        guard let first = try helperWindows(in: stage).last else {
            throw DemoError.missingDemoWindow
        }
        // Make the helper the ACTIVE app before follow engages — otherwise
        // follow's first glide targets the user's terminal (still frontmost
        // and hidden under the shield).
        await driver.click(at: CGPoint(x: first.frame.midX, y: first.frame.midY))
        let shareRect = first.frame.insetBy(dx: -24, dy: -24)
        session.startSharing(rect: shareRect, on: screen)
        try await waitForActive()
        // Pin the preview to the stage's top-right, clear of the follow
        // path: the demo capture includes our own windows, so the region
        // gliding over the panel would create an infinite-mirror portal.
        let previewWidth = stage.width * 0.20
        let previewHeight = previewWidth * shareRect.height / shareRect.width
        session.demoPositionPreview(frame: CGRect(
            x: stage.maxX - previewWidth - 16,
            y: stage.maxY - previewHeight - 16,
            width: previewWidth, height: previewHeight))
        await driver.pause(1.2)

        keystrokeHUD?.show(key: "Follow", caption: "Active window")
        session.setFollow(mode: .activeWindow)
        let targets = try helperWindows(in: stage)
        for window in targets.prefix(2) {
            await driver.click(at: CGPoint(x: window.frame.midX,
                                           y: window.frame.midY))
            await driver.pause(1.6)
        }
        keystrokeHUD?.show(key: "Follow", caption: "Cursor")
        session.setFollow(mode: .cursor)
        await driver.pause(0.5)
        // Waypoints stay in the lower-left two-thirds — never near the
        // pinned preview in the top-right corner.
        for point in [CGPoint(x: stage.minX + stage.width * 0.55,
                              y: stage.minY + stage.height * 0.28),
                      CGPoint(x: stage.minX + stage.width * 0.28,
                              y: stage.minY + stage.height * 0.66),
                      CGPoint(x: stage.minX + stage.width * 0.48,
                              y: stage.minY + stage.height * 0.48)] {
            await driver.move(to: point, over: 1.2)
            await driver.pause(0.6)
        }
        keystrokeHUD?.hide()
        session.setFollow(mode: .off)
        await driver.pause(0.5)
        session.stop()
        await driver.pause(0.8)
        return url
    }

    /// Viewer zoom: the call mirror punches into a 2× window that tracks
    /// the cursor while the stage visibly stays put; then a preset glides
    /// the live region to new content — the share never drops.
    private func zoomScenario(screen: NSScreen) async throws -> URL {
        settings.shareMode = .hiddenWindow
        settings.previewWindowEnabled = false // the call mock is the mirror
        settings.hotbarEnabled = false // the bar would trail both region hops
        settings.zoomFactor = 2.0
        let callFrame = CGRect(x: stage.maxX - stage.width * 0.40 - 16,
                               y: stage.minY + stage.height * 0.16,
                               width: stage.width * 0.40, height: stage.height * 0.52)
        let meet = DemoMeetMock(frame: callFrame)
        meetMock = meet
        session.demoFrameTap = { [weak meet] surface in
            meet?.display(surface: surface)
        }

        // Two 16:9 region slots on the stage's left: notes + metrics fill
        // the TOP one, chat waits in the BOTTOM one for the preset glide.
        // The bottom slot must clear the caption chip at the stage's bottom
        // center — the chip is a live window and would leak into the share.
        let regionW = (stage.width * 0.40).rounded()
        let regionH = (regionW * 9 / 16).rounded()
        let regionTop = CGRect(x: stage.minX + stage.width * 0.035,
                               y: stage.maxY - stage.height * 0.04 - regionH,
                               width: regionW, height: regionH)
        let regionBottom = regionTop.offsetBy(dx: 0,
                                              dy: -(regionH + stage.height * 0.03))
        let sorted = try helperWindows(in: stage).sorted { $0.frame.minX < $1.frame.minX }
        guard sorted.count >= 3 else { throw DemoError.missingDemoWindow }
        WindowMover.move(window: sorted[0], toAppKitOrigin:
            CGPoint(x: regionTop.minX + 8, y: regionTop.minY + 4))
        WindowMover.move(window: sorted[1], toAppKitOrigin:
            CGPoint(x: regionTop.maxX - sorted[1].frame.width - 8,
                    y: regionTop.minY + regionH * 0.10))
        WindowMover.move(window: sorted[2], toAppKitOrigin:
            CGPoint(x: regionBottom.midX - sorted[2].frame.width / 2,
                    y: regionBottom.minY + (regionH - sorted[2].frame.height) / 2))
        // Frontmost hygiene: ours, not whatever the user last used.
        await driver.click(at: titleBarPoint(of: CGRect(
            x: regionTop.minX + 8, y: regionTop.minY + 4,
            width: sorted[0].frame.width, height: sorted[0].frame.height)))
        await driver.pause(0.5)

        let url = try startRecording(screen: screen)
        await driver.pause(0.6)
        session.startSharing(rect: regionTop, on: screen)
        try await waitForActive()
        await driver.pause(1.4)

        // Beat 1: zoom in — the mirror punches in, the stage stays put.
        keystrokeHUD?.show(key: "⌃⌥⌘Z", caption: "Viewers zoom in — your screen stays put")
        await driver.move(to: CGPoint(x: regionTop.minX + regionW * 0.72,
                                      y: regionTop.midY), over: 0.8)
        session.toggleZoom()
        await driver.pause(2.6)

        // Beat 2: the zoom window trails the cursor across the content.
        keystrokeHUD?.show(key: "Zoom", caption: "Follows your cursor")
        await driver.move(to: CGPoint(x: regionTop.minX + regionW * 0.16,
                                      y: regionTop.minY + regionH * 0.62), over: 1.7)
        await driver.pause(0.8)
        await driver.move(to: CGPoint(x: regionTop.minX + regionW * 0.20,
                                      y: regionTop.minY + regionH * 0.22), over: 1.4)
        await driver.pause(0.9)

        // Beat 3: glide back out.
        session.toggleZoom()
        await driver.pause(1.6)

        // Beat 4: live preset switch — the region glides, the share survives.
        keystrokeHUD?.show(key: "⌃⌥⌘1", caption: "Preset — the region glides, the share never stops")
        session.sharePreset(RegionPreset(
            name: "Chat",
            region: StoredRegion(rect: regionBottom, displayID: screen.displayID),
            shareModeRaw: ShareMode.hiddenWindow.rawValue))
        await driver.pause(3.0)
        keystrokeHUD?.hide()
        await driver.pause(0.6)
        session.stop()
        await driver.pause(0.8)
        return url
    }

    /// The capture workflow, driven through the real hotbar: screenshot →
    /// preview card → drag the file into a chat, then record → drag-to-trim
    /// with scrub preview → save, all on the card.
    private func captureScenario(screen: NSScreen) async throws -> URL {
        settings.shareMode = .hiddenWindow
        settings.previewWindowEnabled = false
        settings.hotbarEnabled = true // the bar IS the star of this clip
        settings.recordSystemAudio = false
        settings.recordMicrophone = false // a mic prompt would freeze the take

        // Region high enough that the hotbar (below it) and the card (below
        // the hotbar) stay inside the stage, clear of the caption chip.
        let region = CGRect(x: stage.minX + stage.width * 0.04,
                            y: stage.minY + stage.height * 0.46,
                            width: stage.width * 0.42, height: stage.height * 0.48)
        let chatFrame = CGRect(x: stage.minX + stage.width * 0.55,
                               y: stage.minY + stage.height * 0.12,
                               width: stage.width * 0.21, height: stage.height * 0.36)
        let sorted = try helperWindows(in: stage).sorted { $0.frame.minX < $1.frame.minX }
        guard sorted.count >= 3 else { throw DemoError.missingDemoWindow }
        WindowMover.move(window: sorted[0], toAppKitOrigin:
            CGPoint(x: region.minX + 10, y: region.minY + 10))
        let metricsOrigin = CGPoint(x: region.midX - 20,
                                    y: region.minY + region.height * 0.16)
        WindowMover.move(window: sorted[1], toAppKitOrigin: metricsOrigin)
        WindowMover.move(window: sorted[2], toAppKitOrigin: chatFrame.origin)
        await driver.click(at: titleBarPoint(of: CGRect(
            origin: CGPoint(x: region.minX + 10, y: region.minY + 10),
            size: sorted[0].frame.size)))
        await driver.pause(0.4)

        let url = try startRecording(screen: screen)
        // The scenario's own captures go to a scratch dir the user never
        // sees — redirected AFTER the stage recording started (that one
        // still belongs in Demos).
        savedCaptureFolders = (settings.screenshotFolder,
                               settings.recordingFolder, settings.recentCaptures)
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("OutcutShareDemo", isDirectory: true).path
        settings.screenshotFolder = scratch
        settings.recordingFolder = scratch
        await driver.pause(0.6)
        session.startSharing(rect: region, on: screen)
        try await waitForActive()
        await driver.pause(1.5) // hotbar settles under the region

        // Beat 1: screenshot from the hotbar; the card folds out beneath it.
        keystrokeHUD?.show(key: "Screenshot", caption: "One click on the hotbar")
        guard let camera = session.demoHotbarItemRect("Screenshot shared region") else {
            throw DemoError.missingDemoWindow
        }
        await driver.click(at: CGPoint(x: camera.midX, y: camera.midY))
        let image = try await waitForCardItem("__image__")
        await driver.move(to: CGPoint(x: image.midX, y: image.midY), over: 0.5)
        await driver.pause(1.0)

        // Beat 2: drag the file out of the card, into the chat.
        keystrokeHUD?.show(key: "Drag", caption: "The file goes anywhere — chat, mail, Finder")
        await driver.pause(0.6)
        guard let chat = try helperWindows(in: chatFrame.insetBy(dx: -30, dy: -30))
            .first else {
            throw DemoError.missingDemoWindow
        }
        await driver.drag(from: CGPoint(x: image.midX, y: image.midY),
                          to: CGPoint(x: chat.frame.midX, y: chat.frame.midY - 20),
                          over: 1.5)
        await driver.pause(1.3) // the bubble lands; the card counts down

        // Beat 3: record the region.
        keystrokeHUD?.show(key: "Record", caption: "The region straight to .mp4")
        guard let record = session.demoHotbarItemRect("Start recording") else {
            throw DemoError.missingDemoWindow
        }
        await driver.click(at: CGPoint(x: record.midX, y: record.midY))
        // Motion for the filmstrip: glide over the notes, nudge the metrics
        // window — recorded frames must differ or the trim strip looks dead.
        await driver.move(to: CGPoint(x: region.minX + region.width * 0.22,
                                      y: region.midY + region.height * 0.18), over: 0.9)
        let metricsNow = try helperWindows(in: stage)
            .first { $0.frame.midX > region.midX - 60 && $0.frame.midX < region.maxX }
        if let metricsNow {
            await driver.drag(from: titleBarPoint(of: metricsNow.frame),
                              to: CGPoint(x: metricsNow.frame.midX + 46,
                                          y: metricsNow.frame.maxY - 40),
                              over: 1.1)
        }
        await driver.pause(0.7)
        guard let stop = session.demoHotbarItemRect("Stop recording") else {
            throw DemoError.missingDemoWindow
        }
        await driver.click(at: CGPoint(x: stop.midX, y: stop.midY))
        let video = try await waitForCardItem("__image__")
        await driver.move(to: CGPoint(x: video.midX, y: video.midY), over: 0.5)
        await driver.pause(0.6)

        // Beat 4: trim right on the card — the handles scrub the preview.
        keystrokeHUD?.show(key: "Trim", caption: "Cut it right on the card")
        guard let scissors = session.demoCardItemRect("Trim recording") else {
            throw DemoError.missingDemoWindow
        }
        await driver.click(at: CGPoint(x: scissors.midX, y: scissors.midY))
        await driver.pause(1.2) // the card grows, the filmstrip loads
        guard let strip = session.demoCardItemRect("__timeline__") else {
            throw DemoError.missingDemoWindow
        }
        // The strip's gesture grabs the nearer handle: right end → out.
        // The anchor includes the block's 6 pt padding + time labels — press
        // well inside the filmstrip band or the gesture never sees the drag.
        let stripY = strip.maxY - 26
        await driver.move(to: CGPoint(x: strip.maxX - 16, y: stripY), over: 0.6)
        await driver.press(at: CGPoint(x: strip.maxX - 16, y: stripY))
        await driver.move(to: CGPoint(x: strip.minX + strip.width * 0.62, y: stripY),
                          over: 1.3, dragging: true)
        await driver.release(at: CGPoint(x: strip.minX + strip.width * 0.62, y: stripY))
        await driver.pause(0.5)
        await driver.press(at: CGPoint(x: strip.minX + 16, y: stripY))
        await driver.move(to: CGPoint(x: strip.minX + strip.width * 0.18, y: stripY),
                          over: 1.0, dragging: true)
        await driver.release(at: CGPoint(x: strip.minX + strip.width * 0.18, y: stripY))
        await driver.pause(0.5)
        guard let save = session.demoCardItemRect("Save trimmed copy") else {
            throw DemoError.missingDemoWindow
        }
        await driver.click(at: CGPoint(x: save.midX, y: save.midY))
        await driver.pause(1.8) // export → pop → card back to normal size
        keystrokeHUD?.hide()
        // Step clear so the countdown runs out on film.
        await driver.move(to: CGPoint(x: stage.minX + stage.width * 0.35,
                                      y: stage.minY + stage.height * 0.30), over: 0.7)
        await driver.pause(3.6)
        session.stop()
        await driver.pause(0.6)
        return url
    }

    /// Privacy pause: viewers get a blurred privacy screen with a custom
    /// note while the presenter's own screen stays fully theirs; resume
    /// picks the share back up instantly.
    private func pauseScenario(screen: NSScreen) async throws -> URL {
        settings.shareMode = .hiddenWindow
        settings.previewWindowEnabled = false
        settings.hotbarEnabled = false
        settings.pauseStyle = .privacyScreen
        settings.pauseMessage = "Be right back ☕"
        settings.pauseImagePath = ""
        let callFrame = CGRect(x: stage.maxX - stage.width * 0.40 - 16,
                               y: stage.minY + stage.height * 0.16,
                               width: stage.width * 0.40, height: stage.height * 0.52)
        let meet = DemoMeetMock(frame: callFrame)
        meetMock = meet
        session.demoFrameTap = { [weak meet] surface in
            meet?.display(surface: surface)
        }

        // Notes + metrics fill a 16:9 region up top; the chat waits below,
        // OUTSIDE the region — the private thing handled during the pause.
        let regionW = (stage.width * 0.40).rounded()
        let regionH = (regionW * 9 / 16).rounded()
        let region = CGRect(x: stage.minX + stage.width * 0.035,
                            y: stage.maxY - stage.height * 0.04 - regionH,
                            width: regionW, height: regionH)
        let chatSlot = region.offsetBy(dx: 0, dy: -(regionH + stage.height * 0.03))
        let sorted = try helperWindows(in: stage).sorted { $0.frame.minX < $1.frame.minX }
        guard sorted.count >= 3 else { throw DemoError.missingDemoWindow }
        WindowMover.move(window: sorted[0], toAppKitOrigin:
            CGPoint(x: region.minX + 8, y: region.minY + 4))
        WindowMover.move(window: sorted[1], toAppKitOrigin:
            CGPoint(x: region.maxX - sorted[1].frame.width - 8,
                    y: region.minY + regionH * 0.10))
        let chatOrigin = CGPoint(x: chatSlot.midX - sorted[2].frame.width / 2,
                                 y: chatSlot.minY + (regionH - sorted[2].frame.height) / 2)
        WindowMover.move(window: sorted[2], toAppKitOrigin: chatOrigin)
        await driver.click(at: titleBarPoint(of: CGRect(
            x: region.minX + 8, y: region.minY + 4,
            width: sorted[0].frame.width, height: sorted[0].frame.height)))
        await driver.pause(0.5)

        let url = try startRecording(screen: screen)
        await driver.pause(0.6)
        session.startSharing(rect: region, on: screen)
        try await waitForActive()
        await driver.pause(1.4)

        // Beat 1: pause — the call flips to the privacy screen.
        keystrokeHUD?.show(key: "⌃⌥⌘P", caption: "Pause — viewers see a privacy screen")
        await driver.move(to: CGPoint(x: region.midX, y: region.midY), over: 0.7)
        session.togglePause()
        meet.showPrivacyScreen()
        await driver.pause(3.0)

        // Beat 2: meanwhile the presenter's screen is fully theirs.
        keystrokeHUD?.show(key: "Meanwhile", caption: "Your screen stays yours")
        let chatCenter = CGPoint(x: chatOrigin.x + sorted[2].frame.width / 2,
                                 y: chatOrigin.y + sorted[2].frame.height / 2)
        await driver.click(at: chatCenter)
        await driver.pause(2.6)

        // Beat 3: resume — the share picks up right where it was.
        keystrokeHUD?.show(key: "⌃⌥⌘P", caption: "Resume — live again, instantly")
        session.togglePause()
        meet.hidePrivacyScreen()
        await driver.move(to: CGPoint(x: region.midX + regionW * 0.18,
                                      y: region.midY), over: 1.0)
        await driver.pause(2.2)
        keystrokeHUD?.hide()
        await driver.pause(0.4)
        session.stop()
        await driver.pause(0.8)
        return url
    }

    /// A still of Raycast's root search filtered to the extension — the
    /// one deliberate exception to "touch only helper windows": open the
    /// launcher, type a query, Esc out. No Enter, no drags.
    private func raycastScenario() async throws -> URL {
        NSWorkspace.shared.open(URL(string: "raycast://")!)
        await driver.pause(1.4)
        if raycastWindowID() == nil {
            // The deep link needs Raycast running; a plain activation is
            // the fallback that also starts it.
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Raycast.app"))
            await driver.pause(2.0)
        }
        await typeString("outcut")
        await driver.pause(1.8)
        guard let windowID = raycastWindowID() else {
            throw DemoError.missingDemoWindow
        }
        let dir = settings.recordingFolderURL.appendingPathComponent("Demos")
        try FileManager.default.createDirectory(at: dir,
                                                withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("demo-raycast.png")
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-o", "-l", String(windowID), url.path]
        try capture.run()
        capture.waitUntilExit()
        // Leave Raycast as found: first Esc clears the query, second closes.
        await driver.tapKey(53)
        await driver.tapKey(53)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw DemoError.missingDemoWindow
        }
        return url
    }

    /// Layout-independent typing (German QWERTZ in play): the characters
    /// ride on the event, not on virtual key codes.
    private func typeString(_ text: String) async {
        for unit in Array(text.utf16) {
            var chars = [unit]
            for keyDown in [true, false] {
                let event = CGEvent(keyboardEventSource: nil, virtualKey: 0,
                                    keyDown: keyDown)
                event?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &chars)
                event?.post(tap: .cghidEventTap)
            }
            await driver.pause(0.06)
        }
    }

    private func raycastWindowID() -> CGWindowID? {
        let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)
            as? [[String: Any]] ?? []
        for info in list {
            guard info[kCGWindowOwnerName as String] as? String == "Raycast",
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let width = bounds["Width"] as? Double, width > 300,
                  let number = info[kCGWindowNumber as String] as? Int else { continue }
            return CGWindowID(number)
        }
        return nil
    }

    /// Polls a card anchor until the card is up and its slide-in settled.
    private func waitForCardItem(_ key: String) async throws -> CGRect {
        var last: CGRect?
        for _ in 0..<60 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if let rect = session.demoCardItemRect(key) {
                if let l = last, l == rect { return rect } // two stable reads
                last = rect
            }
        }
        throw DemoError.missingDemoWindow
    }

    // MARK: Plumbing

    private func waitForActive() async throws {
        for _ in 0..<50 {
            if session.isActive { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw DemoError.sessionTimeout
    }

    private func titleBarPoint(of frame: CGRect) -> CGPoint {
        CGPoint(x: frame.midX, y: frame.maxY - 12)
    }

    /// If an interactive drop didn't reach the monitor, place the window
    /// there directly at the intended spot.
    private func ensureLanded(_ id: CGWindowID, panelPoint: CGPoint,
                              panel: CGRect) throws {
        guard let displayFrame = session.currentRegionRect,
              !(try helperWindows(in: displayFrame).contains { $0.id == id }) else {
            return
        }
        guard let stray = try helperWindows(in: stage).first(where: { $0.id == id })
            ?? WindowLocator.frame(ofWindow: id).map({
                WindowLocator.FoundWindow(id: id, pid: helper?.processIdentifier ?? 0,
                                          frame: $0)
            }) else { return }
        let target = Geometry.previewPointToDisplayPoint(panelPoint, panel: panel,
                                                         display: displayFrame)
        let origin = Geometry.centeredClampedWindowOrigin(size: stray.frame.size,
                                                          center: target,
                                                          bounds: displayFrame)
        WindowMover.move(window: stray, toAppKitOrigin: origin, raise: false)
    }

    private func panelPoint(forDisplayPoint p: CGPoint, display: CGRect,
                            panel: CGRect) -> CGPoint {
        // The linear map runs both ways with the rects swapped.
        Geometry.previewPointToDisplayPoint(p, panel: display, display: panel)
    }

    private func cellCenter(_ panel: CGRect, col: Int, row: Int) -> CGPoint {
        CGPoint(x: panel.minX + (CGFloat(col) + 0.5) / 3 * panel.width,
                y: panel.minY + (CGFloat(row) + 0.5) / 3 * panel.height)
    }

    /// The bundled demo wallpaper — app bundle first, repo-relative for
    /// debug-binary runs from the checkout, gradient as the last resort.
    private func backdropImage() -> NSImage? {
        if let url = Bundle.main.url(forResource: "DemoBackdrop", withExtension: "jpg"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return NSImage(contentsOfFile:
            FileManager.default.currentDirectoryPath + "/Resources/DemoBackdrop.jpg")
    }

    private func showBackdrop() {
        let window = NSWindow(contentRect: stage, styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.isOpaque = true
        window.isReleasedWhenClosed = false
        window.level = .normal
        // A shield, not a pass-through: stray presses on empty stage must
        // hit the backdrop, never a user window beneath it.
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        let view = NSView(frame: CGRect(origin: .zero, size: stage.size))
        view.wantsLayer = true
        if let image = backdropImage() {
            view.layer?.contents = image
            view.layer?.contentsGravity = .resizeAspectFill
        } else {
            let gradient = CAGradientLayer()
            gradient.frame = view.bounds
            gradient.colors = [NSColor(calibratedRed: 0.13, green: 0.17, blue: 0.32, alpha: 1).cgColor,
                               NSColor(calibratedRed: 0.34, green: 0.19, blue: 0.38, alpha: 1).cgColor]
            gradient.startPoint = CGPoint(x: 0, y: 1)
            gradient.endPoint = CGPoint(x: 1, y: 0)
            view.layer?.addSublayer(gradient)
        }
        window.contentView = view
        // In FRONT of the user's windows (the whole point: nothing personal
        // in frame); the helper's windows launch afterwards and stack above.
        window.orderFrontRegardless()
        backdrop = window
    }

    private func launchHelper() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        process.arguments = [String(format: "--demo-windows=%.0f,%.0f,%.0f,%.0f",
                                    stage.minX, stage.minY, stage.width, stage.height)]
        try process.run()
        helper = process
        for _ in 0..<50 {
            // Strictly the HELPER's windows — the user's own windows inside
            // the stage area must never satisfy this (or any other) query.
            if (try? helperWindows(in: stage))?.count ?? 0 >= 3 {
                try await Task.sleep(nanoseconds: 500_000_000)
                return
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw DemoError.helperTimeout
    }

    private func startRecording(screen: NSScreen) throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let dir = settings.recordingFolderURL.appendingPathComponent("Demos")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(
            "demo-\(scenario) \(formatter.string(from: Date())).mp4")
        let scale = screen.backingScaleFactor
        let (pw, ph) = Geometry.capturePixelSize(region: stage, scale: scale)
        try recorder.start(pixelWidth: pw, pixelHeight: ph, to: url)
        // Playback speed baked into the file — no post-processing step.
        // The monitor tour reads fine faster; the modifier/follow demos
        // need a touch more time on screen.
        let retimer = SampleRetimer(speed: scenario == "monitor" ? 1.8 : 1.5)
        capture.onSampleBuffer = { [recorder] sample in
            recorder.append(retimer.retimed(sample))
        }
        let local = Geometry.displayLocalTopLeftRect(appKitGlobal: stage,
                                                     screenFrame: screen.frame)
        Task {
            // The demo footage must SHOW our overlays and panels.
            try await capture.start(displayID: screen.displayID,
                                    sourceRectTopLeft: local,
                                    pixelWidth: pw, pixelHeight: ph, fps: 30,
                                    excludedBundleIDs: [],
                                    ownAppExclusion: .none)
        }
        return url
    }

    private func cleanup() async {
        DemoState.active = false
        DemoState.gridModifierForced = false
        keystrokeHUD?.hide()
        if session.state != .idle {
            session.stop()
        }
        session.demoFrameTap = nil
        RegionSelector.demoSelectionObserver = nil
        meetMock?.close()
        helper?.terminate()
        backdrop?.orderOut(nil)
        settings.shareMode = savedMode
        settings.previewWindowEnabled = savedPreview
        settings.followBehavior = savedFollowBehavior
        settings.followResizes = savedFollowResizes
        settings.hotbarEnabled = savedHotbarEnabled
        settings.zoomFactor = savedZoomFactor
        settings.recordSystemAudio = savedRecordSystemAudio
        settings.recordMicrophone = savedRecordMicrophone
        settings.pauseStyle = savedPauseStyle
        settings.pauseMessage = savedPauseMessage
        settings.pauseImagePath = savedPauseImagePath
        if let saved = savedCaptureFolders {
            settings.screenshotFolder = saved.screenshot
            settings.recordingFolder = saved.recording
            settings.recentCaptures = saved.recents
            savedCaptureFolders = nil
        }
        try? await Task.sleep(nanoseconds: 500_000_000)
    }
}
