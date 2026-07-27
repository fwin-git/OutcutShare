import AppKit
import ScreenCaptureKit
import CVirtualDisplay

/// Live permission/health state behind the permissions window. Checkers are
/// injected so the aggregation logic is unit-testable.
@MainActor
final class PermissionsModel: ObservableObject {
    struct Status: Equatable {
        var screenRecordingGranted = false
        var captureWorks = false
        var virtualDisplayAvailable = false
        /// Optional: only drag & drop onto the virtual monitor needs it.
        var accessibilityGranted = false

        /// Everything the app strictly needs to share a region.
        var allSatisfied: Bool { screenRecordingGranted && captureWorks }
        /// TCC says granted but the running process still can't capture —
        /// macOS applies the grant to the next launch.
        var needsRelaunch: Bool { screenRecordingGranted && !captureWorks }
    }

    @Published private(set) var status = Status()

    private let preflight: () -> Bool
    private let captureProbe: () async -> Bool
    private let virtualDisplayCheck: () -> Bool
    private let accessibilityCheck: () -> Bool
    private var pollTask: Task<Void, Never>?

    init(preflight: @escaping () -> Bool = { CGPreflightScreenCaptureAccess() },
         captureProbe: @escaping () async -> Bool = {
             (try? await SCShareableContent.excludingDesktopWindows(false,
                                                                    onScreenWindowsOnly: true)) != nil
         },
         virtualDisplayCheck: @escaping () -> Bool = { CVDApi.available() },
         accessibilityCheck: @escaping () -> Bool = { WindowMover.hasPermission }) {
        self.preflight = preflight
        self.captureProbe = captureProbe
        self.virtualDisplayCheck = virtualDisplayCheck
        self.accessibilityCheck = accessibilityCheck
    }

    func refresh() async {
        var next = Status()
        next.screenRecordingGranted = preflight()
        // Probing while not granted would be pointless and could surface
        // system UI; only verify capture actually works once TCC says yes.
        next.captureWorks = next.screenRecordingGranted ? await captureProbe() : false
        next.virtualDisplayAvailable = virtualDisplayCheck()
        next.accessibilityGranted = accessibilityCheck()
        if next != status {
            status = next
        }
    }

    func requestAccessibility() {
        WindowMover.requestPermission()
    }

    func openAccessibilitySettings() {
        let url = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: url) {
            NSWorkspace.shared.open(url)
        }
    }

    /// Polls while the permissions window is visible so checkmarks update
    /// live as the user flips switches in System Settings.
    func startPolling(interval: TimeInterval = 1.5) {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Triggers the one-time system permission prompt (no-op if macOS has
    /// already recorded a decision for this app).
    func requestScreenRecording() {
        CGRequestScreenCaptureAccess()
    }

    func openSystemSettings() {
        let url = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        if let url = URL(string: url) {
            NSWorkspace.shared.open(url)
        }
    }

    /// Relaunches the bundled app so a fresh TCC grant takes effect.
    func relaunch() {
        let path = Bundle.main.bundlePath
        guard path.hasSuffix(".app") else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", path]
        try? process.run()
        NSApp.terminate(nil)
    }
}
