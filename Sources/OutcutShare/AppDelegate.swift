import AppKit

extension ShareMode {
    fileprivate init?(testArgument: String) {
        switch testArgument {
        case "vd": self = .virtualDisplay
        case "window": self = .hiddenWindow
        case "monitor": self = .virtualMonitor
        default: return nil
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let session = ShareSession()
    private var statusBar: StatusBarController?
    private var permissions: PermissionsWindowController?
    private var hotkeys: HotkeyManager?
    private var debugSettingsWindow: SettingsWindowController?
    private var policyObservers: [NSObjectProtocol] = []

    private var demoContent: DemoContentWindows?
    private var demoDirector: DemoDirector?
    private var debugResultCard: CaptureResultController?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Registered before didFinishLaunching so deep links that *launch*
        // the app (open outcutshare://…) are delivered too.
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleGetURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL))
    }

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor,
                                    withReplyEvent reply: NSAppleEventDescriptor) {
        guard let urlString = event
                .paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: urlString),
              let command = URLCommand.parse(url) else { return }
        handle(command)
    }

    private func handle(_ command: URLCommand) {
        let settings = SettingsStore.shared
        switch command {
        case .select: session.startSelection()
        case .shareLast: session.shareLastRegion()
        case .preset(let id, let name):
            if let preset = URLCommand.matchPreset(id: id, name: name,
                                                   in: settings.presets) {
                session.sharePreset(preset)
            } else {
                presentURLError("No preset matches \"\(name ?? id ?? "")\".")
            }
        case .stop: session.stop()
        case .togglePause: session.togglePause()
        case .toggleRecording: session.toggleRecording()
        case .follow(let mode): session.setFollow(mode: mode)
        case .shareMode(let mode):
            guard session.isIdle else {
                presentURLError("Stop sharing first to switch the share mode.")
                return
            }
            settings.shareMode = mode
        case .toggle(let option):
            switch option {
            case .preview: settings.previewWindowEnabled.toggle()
            case .hotbar: settings.hotbarEnabled.toggle()
            case .cursorHighlights:
                // Halo and ripples act as one presenter switch externally.
                let enabled = !settings.cursorHighlight
                settings.cursorHighlight = enabled
                settings.clickRipples = enabled
            case .dimming: settings.dimmingEnabled.toggle()
            }
        }
    }

    private func presentURLError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Outcut Share"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Demo helper process: only shows the fake stage windows, nothing
        // else (no status item, no onboarding).
        if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--demo-windows=") }) {
            let parts = arg.dropFirst("--demo-windows=".count)
                .split(separator: ",").compactMap { Double($0) }
            if parts.count == 4 {
                demoContent = DemoContentWindows(stage: CGRect(
                    x: parts[0], y: parts[1], width: parts[2], height: parts[3]))
                NSApp.activate(ignoringOtherApps: true)
            }
            return
        }
        let permissions = PermissionsWindowController()
        self.permissions = permissions
        session.onPermissionsNeeded = { permissions.show() }
        statusBar = StatusBarController(session: session, permissions: permissions)
        hotkeys = HotkeyManager { [session] event in
            switch event {
            case .action(.selectRegion): session.startSelection()
            case .action(.adjustRegion): session.startAdjust()
            case .action(.stopSharing): session.stop()
            case .action(.shareLastRegion): session.shareLastRegion()
            case .action(.togglePause): session.togglePause()
            case .action(.toggleRecording): session.toggleRecording()
            case .preset(let index):
                let presets = SettingsStore.shared.presets
                if index < presets.count {
                    session.sharePreset(presets[index])
                }
            }
        }

        if CommandLine.arguments.contains("--hotkeys-test") {
            let lines = (hotkeys?.registered ?? [])
                .map { "\($0.label)=\($0.combo.displayString)" }
            print("HOTKEYS " + lines.joined(separator: " "))
            exit(0)
        }
        if CommandLine.arguments.contains("--permissions-test") {
            Task { @MainActor in
                await permissions.model.refresh()
                let s = permissions.model.status
                print("PERM screenRecording=\(s.screenRecordingGranted ? 1 : 0) "
                    + "captureWorks=\(s.captureWorks ? 1 : 0) "
                    + "virtualDisplay=\(s.virtualDisplayAvailable ? 1 : 0) "
                    + "showOnLaunch=\(s.allSatisfied ? 0 : 1)")
                exit(0)
            }
            return
        }
        if CommandLine.arguments.contains("--show-permissions") {
            permissions.show()
            return
        }
        if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--show-settings") }) {
            let tab = SettingsTab(rawValue: String(arg.dropFirst("--show-settings=".count)))
            let controller = SettingsWindowController(settings: .shared)
            debugSettingsWindow = controller
            controller.show(tab: tab)
            // --close-settings-after=secs closes the window (perf-leak E2E:
            // verifies the tab hierarchy is torn down and timers stop).
            if let closeArg = CommandLine.arguments.first(where: {
                    $0.hasPrefix("--close-settings-after=") }),
               let secs = Double(closeArg.dropFirst("--close-settings-after=".count)) {
                DispatchQueue.main.asyncAfter(deadline: .now() + secs) {
                    NSApp.windows.first {
                        $0.contentViewController is NSTabViewController
                    }?.performClose(nil)
                    NSLog("SETTINGS-CLOSED loaded=%d", controller.isLoaded ? 1 : 0)
                }
            }
            if CommandLine.arguments.contains("--dim-preview") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    DimPreview.shared.begin()
                }
            }
            return
        }
        if CommandLine.arguments.contains("--show-selector") {
            session.startSelection()
            return
        }
        // --result-card-test=/path/img.png shows the capture-result card
        // standalone for 4 s (visual harness for its layout).
        if let cardArg = CommandLine.arguments.first(where: {
                $0.hasPrefix("--result-card-test=") }) {
            let url = URL(fileURLWithPath: String(cardArg.dropFirst("--result-card-test=".count)))
            let controller = CaptureResultController()
            debugResultCard = controller
            let anchor = CGRect(x: 800, y: 700, width: 454, height: 69)
            controller.show(url: url, isVideo: false, near: anchor,
                            on: NSScreen.screens.first)
            print("RESULT-CARD shown")
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { exit(0) }
            return
        }
        // --demo=monitor|region records a feature showcase on a clean 16:9
        // stage (see DemoHarness.swift).
        if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--demo=") }) {
            let director = DemoDirector(session: session,
                                        scenario: String(arg.dropFirst("--demo=".count)))
            demoDirector = director
            director.run()
            return
        }
        observeForDockPolicy()
        runShareTestIfRequested()

        // Guided onboarding: appears whenever the app can't capture yet.
        if !CommandLine.arguments.contains(where: { $0.hasPrefix("--share-test=") }) {
            Task { @MainActor in
                await permissions.model.refresh()
                if !permissions.model.status.allSatisfied {
                    permissions.show()
                }
            }
        }
    }

    /// Dock icon (⌘-Tab / Force Quit presence) appears while a session is
    /// active or the settings window is open — when the setting allows it.
    private func applyActivationPolicy() {
        let settingsVisible = NSApp.windows.contains {
            $0.isVisible && $0.contentViewController is NSTabViewController
        }
        let wantsDock = SettingsStore.shared.dockIconWhileActive
            && (session.state != .idle || settingsVisible)
        let target: NSApplication.ActivationPolicy = wantsDock ? .regular : .accessory
        if NSApp.activationPolicy() != target {
            NSApp.setActivationPolicy(target)
        }
    }

    private func observeForDockPolicy() {
        for name in [settingsChangedNotification, sessionStateChangedNotification,
                     NSWindow.willCloseNotification, NSWindow.didBecomeKeyNotification] {
            policyObservers.append(NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    // Window notifications fire before visibility settles.
                    DispatchQueue.main.async { self?.applyActivationPolicy() }
                }
            })
        }
    }

    /// Debug mode: `--share-test=x,y,w,h,seconds[,vd|window]` shares a fixed
    /// region of the main screen without the interactive selector, reports the
    /// frame count, then exits — used for automated end-to-end verification.
    private func runShareTestIfRequested() {
        guard let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--share-test=") }) else {
            return
        }
        var comps = arg.dropFirst("--share-test=".count).split(separator: ",").map(String.init)
        if let last = comps.last, let mode = ShareMode(testArgument: last) {
            SettingsStore.shared.shareMode = mode
            comps.removeLast()
        }
        let parts = comps.compactMap { Double($0) }
        guard parts.count == 5, let screen = NSScreen.main else {
            print("SHARE-TEST FAIL: usage --share-test=x,y,w,h,seconds[,vd|window]")
            exit(2)
        }
        let rect = CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
        // --preview shows the shared-output preview panel for the whole run.
        if CommandLine.arguments.contains("--preview") {
            SettingsStore.shared.previewWindowEnabled = true
        }
        session.startSharing(rect: rect, on: screen)
        // Optional companion flag: --move-by=dx,dy moves the region halfway
        // through the test run to exercise the live-move path.
        if let moveArg = CommandLine.arguments.first(where: { $0.hasPrefix("--move-by=") }) {
            let delta = moveArg.dropFirst("--move-by=".count).split(separator: ",").compactMap { Double($0) }
            if delta.count == 2 {
                DispatchQueue.main.asyncAfter(deadline: .now() + parts[4] / 2) { [session] in
                    guard let current = session.currentRegionRect else { return }
                    session.moveRegion(to: CGPoint(x: current.minX + delta[0],
                                                   y: current.minY + delta[1]))
                    print("SHARE-TEST moved region to \(session.currentRegionRect.map(String.init(describing:)) ?? "?")")
                }
            }
        }
        // --follow=activeWindow|cursor enables follow mode 2 s into the run.
        if let followArg = CommandLine.arguments.first(where: { $0.hasPrefix("--follow=") }) {
            if let mode = FollowMode(rawValue: String(followArg.dropFirst("--follow=".count))) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [session] in
                    session.setFollow(mode: mode)
                    print("SHARE-TEST follow=\(mode.rawValue)")
                }
            }
        }
        // --record-at=t1,t2 toggles recording at the given offsets (seconds).
        if let recordArg = CommandLine.arguments.first(where: { $0.hasPrefix("--record-at=") }) {
            let times = recordArg.dropFirst("--record-at=".count).split(separator: ",").compactMap { Double($0) }
            for time in times {
                DispatchQueue.main.asyncAfter(deadline: .now() + time) { [session] in
                    session.toggleRecording()
                    print("SHARE-TEST recording toggled, recording=\(session.isRecording)")
                }
            }
        }
        // --screenshot-at=t1,t2 saves region screenshots at the given offsets.
        if let shotArg = CommandLine.arguments.first(where: { $0.hasPrefix("--screenshot-at=") }) {
            let times = shotArg.dropFirst("--screenshot-at=".count).split(separator: ",").compactMap { Double($0) }
            for time in times {
                DispatchQueue.main.asyncAfter(deadline: .now() + time) { [session] in
                    session.captureScreenshot()
                    print("SHARE-TEST screenshot requested")
                }
            }
        }
        // --pause-at=t1,t2 toggles pause at the given offsets (seconds).
        if let pauseArg = CommandLine.arguments.first(where: { $0.hasPrefix("--pause-at=") }) {
            let times = pauseArg.dropFirst("--pause-at=".count).split(separator: ",").compactMap { Double($0) }
            for time in times {
                DispatchQueue.main.asyncAfter(deadline: .now() + time) { [session] in
                    session.togglePause()
                    print("SHARE-TEST pause toggled, paused=\(session.isPaused)")
                }
            }
        }
        // --resize-by=dw,dh grows the region (bottom-left anchored) at 2/3 of
        // the test run; the mode's aspect constraint applies.
        if let resizeArg = CommandLine.arguments.first(where: { $0.hasPrefix("--resize-by=") }) {
            let delta = resizeArg.dropFirst("--resize-by=".count).split(separator: ",").compactMap { Double($0) }
            if delta.count == 2 {
                DispatchQueue.main.asyncAfter(deadline: .now() + parts[4] * 2 / 3) { [session] in
                    session.resizeRegion(byWidth: delta[0], height: delta[1])
                    print("SHARE-TEST resized region to \(session.currentRegionRect.map(String.init(describing:)) ?? "?")")
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + parts[4]) { [session] in
            let frames = session.receivedFrameCount
            let active = session.isActive
            session.stop()
            print("SHARE-TEST \(active && frames > 0 ? "OK" : "FAIL") active=\(active) frames=\(frames)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                exit(active && frames > 0 ? 0 : 1)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        session.stop()
    }
}
