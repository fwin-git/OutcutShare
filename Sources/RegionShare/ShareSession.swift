import AppKit

/// Owns the lifecycle of one sharing session: selection, virtual display,
/// capture, projection and dimming.
@MainActor
final class ShareSession {
    enum State { case idle, selecting, active }

    private(set) var state: State = .idle {
        didSet { onStateChange?() }
    }
    var onStateChange: (() -> Void)?
    var isActive: Bool { state == .active }

    private nonisolated(unsafe) let settings: SettingsStore
    private var selector: RegionSelector?
    private var virtualDisplay: VirtualDisplay?
    private var capture: CaptureEngine?
    private var projection: ProjectionWindow?
    private var overlay: DimOverlay?
    private var currentRegion: SelectedRegion?
    private var activeFrameRate = 0
    private var settingsObserver: NSObjectProtocol?

    nonisolated init(settings: SettingsStore = .shared) {
        self.settings = settings
    }

    func startSelection() {
        guard state == .idle else { return }
        if !CGPreflightScreenCaptureAccess() {
            // Trigger the system prompt before the selection overlay appears.
            CGRequestScreenCaptureAccess()
        }
        state = .selecting
        let selector = RegionSelector()
        self.selector = selector
        selector.begin { [weak self] region in
            guard let self else { return }
            self.selector = nil
            guard let region else {
                self.state = .idle
                return
            }
            Task { await self.activate(region: region) }
        }
    }

    /// Programmatic entry used by the --share-test debug mode.
    func startSharing(rect: CGRect, on screen: NSScreen) {
        guard state == .idle else { return }
        state = .selecting
        Task { await activate(region: SelectedRegion(rect: rect, screen: screen)) }
    }

    func stop() {
        guard state != .idle else { return }
        teardown()
        state = .idle
    }

    /// Frames received by the active capture stream (debug/testing aid).
    var receivedFrameCount: Int { capture?.frameCount ?? 0 }

    private func activate(region: SelectedRegion) async {
        do {
            let sourceScale = region.screen.backingScaleFactor
            let vd = try VirtualDisplay(sizeInPoints: region.rect.size,
                                        scale: sourceScale, name: "Region Share")
            virtualDisplay = vd
            let virtualScreen = try await vd.waitForScreen()
            let projection = ProjectionWindow(screen: virtualScreen)
            self.projection = projection
            // Created before the capture filter snapshots the window list so
            // the overlay is genuinely excluded from the captured picture.
            overlay = DimOverlay(region: region.rect, screen: region.screen, settings: settings)

            let capture = CaptureEngine()
            self.capture = capture
            capture.onFrame = { [weak projection] surface in
                projection?.display(surface: surface)
            }
            capture.onStopped = { [weak self] error in
                Task { @MainActor in self?.handleStreamStopped(error) }
            }
            let sourceRect = Geometry.displayLocalTopLeftRect(appKitGlobal: region.rect,
                                                             screenFrame: region.screen.frame)
            let (pw, ph) = Geometry.capturePixelSize(region: region.rect, scale: sourceScale)
            try await capture.start(displayID: region.displayID, sourceRectTopLeft: sourceRect,
                                    pixelWidth: pw, pixelHeight: ph, fps: settings.frameRate)

            currentRegion = region
            activeFrameRate = settings.frameRate
            observeSettingsChanges()
            state = .active
        } catch {
            teardown()
            state = .idle
            presentError(error)
        }
    }

    private func observeSettingsChanges() {
        guard settingsObserver == nil else { return }
        settingsObserver = NotificationCenter.default.addObserver(
            forName: settingsChangedNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.frameRateChangedIfNeeded()
            }
        }
    }

    private func frameRateChangedIfNeeded() {
        guard state == .active, settings.frameRate != activeFrameRate,
              let region = currentRegion, let capture else { return }
        activeFrameRate = settings.frameRate
        let fps = activeFrameRate
        Task {
            await capture.stop()
            let sourceScale = region.screen.backingScaleFactor
            let sourceRect = Geometry.displayLocalTopLeftRect(appKitGlobal: region.rect,
                                                             screenFrame: region.screen.frame)
            let (pw, ph) = Geometry.capturePixelSize(region: region.rect, scale: sourceScale)
            do {
                try await capture.start(displayID: region.displayID, sourceRectTopLeft: sourceRect,
                                        pixelWidth: pw, pixelHeight: ph, fps: fps)
            } catch {
                handleStreamStopped(error)
            }
        }
    }

    private func handleStreamStopped(_ error: Error?) {
        guard state == .active else { return }
        teardown()
        state = .idle
        if let error {
            presentError(error, title: "Sharing stopped")
        }
    }

    private func teardown() {
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
            self.settingsObserver = nil
        }
        if let capture {
            capture.onStopped = nil
            capture.onFrame = nil
            Task { await capture.stop() }
        }
        capture = nil
        overlay?.close()
        overlay = nil
        projection?.close()
        projection = nil
        virtualDisplay?.destroy()
        virtualDisplay = nil
        currentRegion = nil
    }

    private func presentError(_ error: Error, title: String = "RegionShare couldn't start sharing") {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        NSApp.activate(ignoringOtherApps: true)
        if case CaptureEngine.CaptureError.permissionDenied = error {
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "OK")
            if alert.runModal() == .alertFirstButtonReturn,
               let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        } else {
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}
