import AppKit

/// One-time copy of settings from the app's previous identity
/// (com.regionshare.app) so presets, hotkeys and preferences survive the
/// rename. Runs before anything touches SettingsStore.
enum SettingsMigration {
    static func run() {
        guard Bundle.main.bundleIdentifier == "com.outcutshare.app" else { return }
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "didMigrateFromRegionShare") else { return }
        defaults.set(true, forKey: "didMigrateFromRegionShare")
        guard let oldValues = UserDefaults(suiteName: "com.regionshare.app")?
            .persistentDomain(forName: "com.regionshare.app"), !oldValues.isEmpty else {
            return
        }
        for (key, value) in oldValues where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }
    }
}

@main
struct OutcutShareApp {
    @MainActor
    static func main() {
        SettingsMigration.run()
        if CommandLine.arguments.contains("--vd-test") {
            virtualDisplayTest()
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    /// Headless smoke test for the private virtual display API: creates a
    /// 1280×720 display, waits for its NSScreen, tears it down again.
    @MainActor
    private static func virtualDisplayTest() {
        do {
            let vd = try VirtualDisplay(sizeInPoints: CGSize(width: 1280, height: 720),
                                        scale: 1, name: "Outcut Share Test")
            print("VD-TEST created displayID=\(vd.displayID)")
            var screen: NSScreen?
            let deadline = Date().addingTimeInterval(5)
            while screen == nil && Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
                screen = NSScreen.screen(for: vd.displayID)
            }
            if let screen {
                print("VD-TEST OK frame=\(screen.frame) scale=\(screen.backingScaleFactor) name=\(screen.localizedName)")
            } else {
                print("VD-TEST FAIL: screen never appeared")
            }
            vd.destroy()
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
            exit(screen != nil ? 0 : 1)
        } catch {
            print("VD-TEST FAIL: \(error.localizedDescription)")
            exit(1)
        }
    }
}
