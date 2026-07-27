import AppKit

enum FollowMode: String, CaseIterable {
    case off
    case activeWindow
    case cursor

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .activeWindow: return "Active Window"
        case .cursor: return "Cursor"
        }
    }
}

/// Moves the active region automatically: after the focused window, or after
/// the cursor (camera-style with a dead zone). Movement either snaps or
/// glides toward the target depending on settings.
@MainActor
final class FollowController {
    private weak var session: ShareSession?
    private let settings: SettingsStore
    private var timer: Timer?
    private var target: CGRect?
    private var tickCount = 0

    private(set) var mode: FollowMode = .off

    init(session: ShareSession, settings: SettingsStore) {
        self.session = session
        self.settings = settings
    }

    func set(mode: FollowMode) {
        self.mode = mode
        timer?.invalidate()
        timer = nil
        target = nil
        tickCount = 0
        guard mode != .off else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        guard let session, session.state == .active,
              let current = session.currentRegionRect,
              let screen = session.currentScreen else {
            set(mode: .off)
            return
        }
        tickCount += 1
        switch mode {
        case .activeWindow:
            // Window lookups are comparatively expensive — refresh ~4×/s.
            if tickCount % 8 == 1 {
                target = windowTarget(current: current, screen: screen)
            }
        case .cursor:
            let shift = Geometry.deadZoneShift(region: current, point: NSEvent.mouseLocation,
                                               margin: 80)
            if shift != .zero {
                let origin = Geometry.clampedRegionOrigin(
                    CGPoint(x: current.minX + shift.width, y: current.minY + shift.height),
                    regionSize: current.size, screenFrame: screen.frame)
                target = CGRect(origin: origin, size: current.size)
            }
        case .off:
            return
        }
        guard let target, target != current else { return }
        if settings.followBehavior == .snap {
            session.setRegionRect(target)
            self.target = nil
            return
        }
        // Glide: exponential ease toward the target.
        let next = Self.lerp(from: current, to: target, fraction: 0.22)
        if Self.isClose(next, to: target) {
            session.setRegionRect(target)
            self.target = nil
        } else {
            session.setRegionRect(next)
        }
    }

    private func windowTarget(current: CGRect, screen: NSScreen) -> CGRect? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let primary = NSScreen.screens.first,
              let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        let frame = info.lazy.compactMap { entry -> CGRect? in
            guard (entry[kCGWindowLayer as String] as? Int) == 0,
                  (entry[kCGWindowOwnerPID as String] as? Int32) == app.processIdentifier,
                  let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let cgRect = CGRect(dictionaryRepresentation: boundsDict),
                  cgRect.width >= 64, cgRect.height >= 64 else {
                return nil
            }
            return Geometry.appKitRect(fromCGTopLeft: cgRect, primaryHeight: primary.frame.height)
        }.first
        guard let frame, screen.frame.contains(CGPoint(x: frame.midX, y: frame.midY)) else {
            return nil
        }
        if settings.followResizes {
            return Geometry.aspectFittedRect(around: frame, aspect: session?.currentAspect,
                                             screenFrame: screen.frame)
        }
        let origin = Geometry.clampedRegionOrigin(
            CGPoint(x: frame.midX - current.width / 2, y: frame.midY - current.height / 2),
            regionSize: current.size, screenFrame: screen.frame)
        return CGRect(origin: origin, size: current.size)
    }

    private static func lerp(from: CGRect, to: CGRect, fraction: CGFloat) -> CGRect {
        CGRect(x: from.minX + (to.minX - from.minX) * fraction,
               y: from.minY + (to.minY - from.minY) * fraction,
               width: from.width + (to.width - from.width) * fraction,
               height: from.height + (to.height - from.height) * fraction)
    }

    private static func isClose(_ a: CGRect, to b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 1 && abs(a.minY - b.minY) < 1
            && abs(a.width - b.width) < 1 && abs(a.height - b.height) < 1
    }
}
