import AppKit

/// Viewers-only zoom: glides the capture window (a sub-rect of the region)
/// toward the cursor while the on-screen region, dim and overlays stay put.
/// The fixed stream output scales the smaller sourceRect up — that IS the
/// zoom. Mirrors FollowController's timer/glide mechanics.
@MainActor
final class ZoomController {
    private weak var session: ShareSession?
    private let settings: SettingsStore
    private var timer: Timer?
    /// Capture window currently applied (region coords, AppKit global).
    private var current: CGRect?
    /// Where the glide is headed: zoom window while zoomed, region on exit.
    private var target: CGRect?
    private(set) var isZoomed = false

    init(session: ShareSession, settings: SettingsStore) {
        self.session = session
        self.settings = settings
    }

    func toggle() {
        isZoomed ? zoomOut() : zoomIn()
    }

    private func zoomIn() {
        guard let session, session.isActive, !session.isVirtualMonitor,
              let region = session.currentRegionRect else { return }
        isZoomed = true
        if current == nil { current = region }
        target = Geometry.zoomWindow(region: region, focus: NSEvent.mouseLocation,
                                     factor: settings.zoomFactor)
        startTimer()
    }

    private func zoomOut() {
        guard isZoomed else { return }
        isZoomed = false
        target = session?.currentRegionRect
        startTimer()
    }

    /// Immediate reset without a capture update — used when the region
    /// itself moves/resizes (that path re-points the stream anyway) and on
    /// teardown.
    func cancel() {
        timer?.invalidate()
        timer = nil
        isZoomed = false
        current = nil
        target = nil
    }

    private func startTimer() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        guard let session, session.isActive,
              let region = session.currentRegionRect,
              let currentNow = current, var targetNow = target else {
            cancel()
            return
        }
        if isZoomed {
            // Track the cursor with a dead zone, like cursor follow — but
            // inside the region only, and clamped to it.
            let mouse = NSEvent.mouseLocation
            if region.contains(mouse) {
                let margin = min(targetNow.width, targetNow.height) * 0.22
                let shift = Geometry.deadZoneShift(region: targetNow, point: mouse,
                                                   margin: margin)
                if shift != .zero {
                    let origin = Geometry.clampedRegionOrigin(
                        CGPoint(x: targetNow.minX + shift.width,
                                y: targetNow.minY + shift.height),
                        regionSize: targetNow.size, screenFrame: region)
                    targetNow = CGRect(origin: origin, size: targetNow.size)
                    target = targetNow
                }
            }
        }
        // Soft exponential glide — same feel as follow's glide.
        let next = Geometry.lerp(from: currentNow, to: targetNow, fraction: 0.16)
        if Geometry.rectsClose(next, targetNow, tolerance: 0.5) {
            current = targetNow
            session.applyZoomWindow(targetNow)
            if !isZoomed {
                // Settled back on the full region — zoom is over.
                timer?.invalidate()
                timer = nil
                current = nil
                target = nil
            }
        } else {
            current = next
            session.applyZoomWindow(next)
        }
    }

}
