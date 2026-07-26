import AppKit

extension ShareMode {
    fileprivate init?(testArgument: String) {
        switch testArgument {
        case "vd": self = .virtualDisplay
        case "window": self = .hiddenWindow
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        let permissions = PermissionsWindowController()
        self.permissions = permissions
        session.onPermissionsNeeded = { permissions.show() }
        statusBar = StatusBarController(session: session, permissions: permissions)
        hotkeys = HotkeyManager { [session] action in
            switch action {
            case .selectRegion: session.startSelection()
            case .adjustRegion: session.startAdjust()
            case .stopSharing: session.stop()
            }
        }

        if CommandLine.arguments.contains("--hotkeys-test") {
            let lines = (hotkeys?.registered ?? [])
                .map { "\($0.action.rawValue)=\($0.combo.displayString)" }
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
            return
        }
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
