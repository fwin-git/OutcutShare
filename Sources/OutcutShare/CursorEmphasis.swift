import AppKit

/// Draws cursor emphasis (halo, click ripples) into the shared output only:
/// layers live on the output window, so viewers see them while the
/// presenter's actual screen stays untouched.
@MainActor
final class CursorEmphasisController {
    private let settings: SettingsStore
    private weak var session: ShareSession?
    private weak var output: LiveFrameWindow?
    private var timer: Timer?
    private var clickMonitor: Any?
    private var localClickMonitor: Any?

    init(session: ShareSession, settings: SettingsStore) {
        self.session = session
        self.settings = settings
    }

    func start(output: LiveFrameWindow) {
        self.output = output
        stopTimers()
        guard settings.cursorHighlight || settings.clickRipples else { return }
        if settings.cursorHighlight {
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
        }
        if settings.clickRipples {
            clickMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.click() }
            }
            localClickMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]
            ) { [weak self] event in
                MainActor.assumeIsolated { self?.click() }
                return event
            }
        }
    }

    func stop() {
        stopTimers()
        output?.showCursorHalo(at: nil)
        output = nil
    }

    /// Re-evaluates enabled toggles (settings changed mid-session).
    func settingsChanged() {
        guard let output else { return }
        start(output: output)
        if !settings.cursorHighlight {
            output.showCursorHalo(at: nil)
        }
    }

    private func stopTimers() {
        timer?.invalidate()
        timer = nil
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
        }
        clickMonitor = nil
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
        }
        localClickMonitor = nil
    }

    private func mappedCursorPosition() -> CGPoint? {
        guard let session, session.state == .active, !session.isPaused,
              let region = session.currentRegionRect,
              let output else { return nil }
        let mouse = NSEvent.mouseLocation
        guard region.contains(mouse) else { return nil }
        let size = output.contentSize
        guard region.width > 0, region.height > 0 else { return nil }
        return CGPoint(x: (mouse.x - region.minX) / region.width * size.width,
                       y: (mouse.y - region.minY) / region.height * size.height)
    }

    private func tick() {
        output?.showCursorHalo(at: mappedCursorPosition())
    }

    private func click() {
        guard settings.clickRipples, let point = mappedCursorPosition() else { return }
        output?.spawnRipple(at: point)
    }
}
