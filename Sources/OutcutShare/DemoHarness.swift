import AppKit
import CoreGraphics

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
    private var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    private func post(_ type: CGEventType, at appKit: CGPoint,
                      button: CGMouseButton = .left) {
        let point = Geometry.cgPoint(fromAppKit: appKit, primaryHeight: primaryHeight)
        guard let event = CGEvent(mouseEventSource: nil, mouseType: type,
                                  mouseCursorPosition: point, mouseButton: button) else {
            return
        }
        event.post(tap: .cghidEventTap)
    }

    func pause(_ seconds: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    /// Eased cursor glide, ~60 Hz.
    func move(to target: CGPoint, over duration: TimeInterval,
              dragging: Bool = false) async {
        let start = NSEvent.mouseLocation
        let steps = max(2, Int(duration * 60))
        for i in 1...steps {
            let t = Double(i) / Double(steps)
            let eased = t * t * (3 - 2 * t) // smoothstep
            let p = CGPoint(x: start.x + (target.x - start.x) * eased,
                            y: start.y + (target.y - start.y) * eased)
            post(dragging ? .leftMouseDragged : .mouseMoved, at: p)
            await pause(duration / Double(steps))
        }
    }

    func press(at p: CGPoint) async {
        post(.leftMouseDown, at: p)
        await pause(0.08)
    }

    func release(at p: CGPoint) async {
        post(.leftMouseUp, at: p)
        await pause(0.15)
    }

    /// A full grab-move-drop of whatever is under `from`.
    func drag(from: CGPoint, to: CGPoint, over duration: TimeInterval) async {
        await move(to: from, over: 0.6)
        await press(at: from)
        await move(to: to, over: duration, dragging: true)
        await release(at: to)
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
        hide()
        let font = NSFont.systemFont(ofSize: 34, weight: .bold)
        let text = NSAttributedString(string: label,
                                      attributes: [.font: font,
                                                   .foregroundColor: NSColor.white])
        let textSize = text.size()
        let frame = CGRect(x: stage.midX - (textSize.width + 60) / 2,
                           y: stage.minY + 24,
                           width: textSize.width + 60, height: textSize.height + 26)
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
        view.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor
        view.layer?.cornerRadius = 14
        let field = NSTextField(labelWithAttributedString: text)
        field.frame = CGRect(x: (frame.width - textSize.width) / 2,
                             y: (frame.height - textSize.height) / 2,
                             width: textSize.width, height: textSize.height)
        view.addSubview(field)
        panel.contentView = view
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}

/// `--demo=<scenario>` — sets a clean 16:9 stage on the main screen, spawns
/// the helper's fake windows, choreographs real interactions with synthetic
/// input and records the stage to an .mp4. Scenarios: `monitor`, `region`.
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
        stage = Geometry.demoStageRect(visibleFrame: screen.visibleFrame)
        keystrokeHUD = DemoKeystrokeHUD(stage: stage)
        showBackdrop()
        try await launchHelper()
        print("DEMO starting in 3s — hands off mouse & keyboard (Ctrl-C aborts)")
        await driver.pause(3.0)

        let url: URL
        switch scenario {
        case "monitor":
            url = try await monitorScenario(screen: screen)
        case "region":
            url = try await regionScenario(screen: screen)
        default:
            throw DemoError.unknownScenario
        }

        await driver.pause(1.5)
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
        await driver.move(to: CGPoint(x: stage.minX + 60, y: stage.minY + 60), over: 0.4)
        await driver.pause(0.6)
        let url = try startRecording(screen: screen)
        await driver.pause(1.2)

        // Drag two fake app windows onto the monitor.
        guard let notes = try helperWindows(in: stage).first else {
            throw DemoError.missingDemoWindow
        }
        await driver.drag(from: titleBarPoint(of: notes.frame),
                          to: CGPoint(x: panel.minX + panel.width * 0.30,
                                      y: panel.minY + panel.height * 0.62),
                          over: 1.6)
        await driver.pause(1.4)
        guard let second = try helperWindows(in: stage).first else {
            throw DemoError.missingDemoWindow
        }
        await driver.drag(from: titleBarPoint(of: second.frame),
                          to: CGPoint(x: panel.minX + panel.width * 0.62,
                                      y: panel.minY + panel.height * 0.52),
                          over: 1.8)
        await driver.pause(1.4)

        // Grid layout: grab a window inside the preview, sweep a block.
        guard let displayFrame = session.currentRegionRect else { return url }
        let onMonitor = try helperWindows(in: displayFrame)
        if let target = onMonitor.first {
            let grab = panelPoint(forDisplayPoint:
                CGPoint(x: target.frame.midX, y: target.frame.maxY - 14),
                display: displayFrame, panel: panel)
            await driver.move(to: grab, over: 0.7)
            await driver.press(at: grab)
            await driver.move(to: cellCenter(panel, col: 0, row: 1), over: 0.7,
                              dragging: true)
            DemoState.gridModifierForced = true
            keystrokeHUD?.show(settings.dragOutModifier.symbol)
            await driver.move(to: cellCenter(panel, col: 0, row: 1), over: 0.4,
                              dragging: true)
            await driver.move(to: cellCenter(panel, col: 0, row: 0), over: 0.8,
                              dragging: true)
            await driver.release(at: cellCenter(panel, col: 0, row: 0))
            DemoState.gridModifierForced = false
            keystrokeHUD?.hide()
            await driver.pause(1.4)
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
                              over: 1.8)
            await driver.pause(1.6)
        }

        session.stop() // remaining windows return automatically
        await driver.pause(2.2)
        return url
    }

    private func regionScenario(screen: NSScreen) async throws -> URL {
        settings.shareMode = .hiddenWindow
        settings.previewWindowEnabled = true
        let url = try startRecording(screen: screen)
        await driver.pause(0.8)
        session.startSelection()
        await driver.pause(0.8)
        // Draw a region around the fake windows on the stage's left side.
        let from = CGPoint(x: stage.minX + stage.width * 0.03,
                           y: stage.minY + stage.height * 0.06)
        let to = CGPoint(x: stage.minX + stage.width * 0.56,
                         y: stage.minY + stage.height * 0.92)
        await driver.drag(from: from, to: to, over: 1.6)
        try await waitForActive()
        await driver.pause(2.0)
        session.togglePause()
        await driver.pause(1.8)
        session.togglePause()
        await driver.pause(1.4)
        session.stop()
        await driver.pause(1.0)
        return url
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

    private func panelPoint(forDisplayPoint p: CGPoint, display: CGRect,
                            panel: CGRect) -> CGPoint {
        // The linear map runs both ways with the rects swapped.
        Geometry.previewPointToDisplayPoint(p, panel: display, display: panel)
    }

    private func cellCenter(_ panel: CGRect, col: Int, row: Int) -> CGPoint {
        CGPoint(x: panel.minX + (CGFloat(col) + 0.5) / 3 * panel.width,
                y: panel.minY + (CGFloat(row) + 0.5) / 3 * panel.height)
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
        let gradient = CAGradientLayer()
        gradient.frame = view.bounds
        gradient.colors = [NSColor(calibratedRed: 0.13, green: 0.17, blue: 0.32, alpha: 1).cgColor,
                           NSColor(calibratedRed: 0.34, green: 0.19, blue: 0.38, alpha: 1).cgColor]
        gradient.startPoint = CGPoint(x: 0, y: 1)
        gradient.endPoint = CGPoint(x: 1, y: 0)
        view.layer?.addSublayer(gradient)
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
        capture.onSampleBuffer = { [recorder] sample in
            recorder.append(sample)
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
        helper?.terminate()
        backdrop?.orderOut(nil)
        settings.shareMode = savedMode
        settings.previewWindowEnabled = savedPreview
        try? await Task.sleep(nanoseconds: 500_000_000)
    }
}
