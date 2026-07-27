import AppKit
import ApplicationServices

/// CGWindowList lookups for other apps' windows (global CG coordinates are
/// converted to AppKit space at the boundary).
enum WindowLocator {
    struct FoundWindow {
        let id: CGWindowID
        let pid: pid_t
        /// AppKit global coordinates.
        let frame: CGRect
    }

    private static var primaryHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }

    /// Frontmost normal-layer window of another app under `point`.
    static func frontmostWindow(at appKitPoint: CGPoint,
                                excludingPID: pid_t) -> FoundWindow? {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return nil }
        for info in list {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  pid != excludingPID,
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let frame = appKitFrame(fromBoundsDict: info[kCGWindowBounds as String])
            else { continue }
            if frame.contains(appKitPoint) {
                return FoundWindow(id: id, pid: pid, frame: frame)
            }
        }
        return nil
    }

    /// Current AppKit frame of a specific window (nil once it's gone).
    static func frame(ofWindow id: CGWindowID) -> CGRect? {
        guard let list = CGWindowListCopyWindowInfo(.optionIncludingWindow, id)
                as? [[String: Any]],
              let info = list.first else { return nil }
        return appKitFrame(fromBoundsDict: info[kCGWindowBounds as String])
    }

    private static func appKitFrame(fromBoundsDict value: Any?) -> CGRect? {
        guard let b = value as? [String: CGFloat] else { return nil }
        let cg = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0,
                        width: b["Width"] ?? 0, height: b["Height"] ?? 0)
        return Geometry.appKitRect(fromCGTopLeft: cg, primaryHeight: primaryHeight)
    }
}

/// Moves other apps' windows via the Accessibility API. Requires the
/// (optional) Accessibility permission; everything degrades gracefully
/// without it.
enum WindowMover {
    static var hasPermission: Bool { AXIsProcessTrusted() }

    /// Triggers the one-time system prompt.
    static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    /// Repositions another app's window (AppKit-global target origin) and
    /// raises it. Returns false when the AX window can't be resolved.
    @discardableResult
    static func move(window: WindowLocator.FoundWindow, toAppKitOrigin origin: CGPoint) -> Bool {
        guard let currentFrame = WindowLocator.frame(ofWindow: window.id),
              let axWindow = axWindow(for: window, frame: currentFrame) else { return false }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        var point = Geometry.cgTopLeftPoint(
            forAppKit: CGRect(origin: origin, size: currentFrame.size),
            primaryHeight: primaryHeight)
        guard let value = AXValueCreate(.cgPoint, &point) else { return false }
        let result = AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString,
                                                  value)
        AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
        return result == .success
    }

    /// There is no public CGWindowID → AXUIElement bridge: match the app's
    /// AX windows against the CG window's current frame.
    private static func axWindow(for window: WindowLocator.FoundWindow,
                                 frame target: CGRect) -> AXUIElement? {
        let app = AXUIElementCreateApplication(window.pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString,
                                            &value) == .success,
              let windows = value as? [AXUIElement] else { return nil }
        var best: (element: AXUIElement, distance: CGFloat)?
        for element in windows {
            guard let frame = frame(of: element) else { continue }
            let distance = abs(frame.minX - target.minX) + abs(frame.minY - target.minY)
                + abs(frame.width - target.width) + abs(frame.height - target.height)
            if best == nil || distance < best!.distance {
                best = (element, distance)
            }
        }
        // Within a few points — otherwise we'd grab the wrong window.
        guard let best, best.distance < 8 else { return nil }
        return best.element
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString,
                                            &positionRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString,
                                            &sizeRef) == .success else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionRef as! AXValue, .cgPoint, &point),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size) else { return nil }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return Geometry.appKitRect(
            fromCGTopLeft: CGRect(origin: point, size: size),
            primaryHeight: primaryHeight)
    }
}

/// Watches global window drags while a virtual-monitor session runs:
/// dropping another app's window onto the preview panel moves that window
/// onto the virtual display, at the spot it was dropped.
@MainActor
final class MonitorDragController {
    private weak var session: ShareSession?
    private weak var preview: PreviewWindowController?
    private var displayFrame: CGRect = .zero
    private var monitors: [Any] = []
    private var candidate: (window: WindowLocator.FoundWindow, start: CGPoint)?

    init(session: ShareSession) {
        self.session = session
    }

    func start(displayFrame: CGRect, preview: PreviewWindowController) {
        stop()
        self.displayFrame = displayFrame
        self.preview = preview
        monitors = [
            NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
                MainActor.assumeIsolated { self?.mouseDown() }
            },
            NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
                MainActor.assumeIsolated { self?.mouseDragged() }
            },
            NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
                MainActor.assumeIsolated { self?.mouseUp() }
            },
        ].compactMap { $0 }
    }

    func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        candidate = nil
        preview?.setDropTargetHighlight(false)
    }

    private func mouseDown() {
        let point = NSEvent.mouseLocation
        // Presses on our own panel are never window drags from outside.
        if preview?.panelFrame?.contains(point) == true {
            candidate = nil
            return
        }
        candidate = WindowLocator.frontmostWindow(at: point, excludingPID: getpid())
            .map { ($0, point) }
    }

    private func mouseDragged() {
        guard candidate != nil, let panel = preview?.panelFrame else { return }
        preview?.setDropTargetHighlight(panel.contains(NSEvent.mouseLocation))
    }

    private func mouseUp() {
        defer {
            preview?.setDropTargetHighlight(false)
            candidate = nil
        }
        guard let candidate, let panel = preview?.panelFrame else { return }
        let end = NSEvent.mouseLocation
        guard let currentFrame = WindowLocator.frame(ofWindow: candidate.window.id),
              Geometry.isWindowDropOnPanel(start: candidate.start, end: end, panel: panel,
                                           windowFrameAtStart: candidate.window.frame,
                                           windowFrameAtEnd: currentFrame) else { return }
        guard WindowMover.hasPermission else {
            WindowMover.requestPermission()
            session?.onPermissionsNeeded?()
            return
        }
        let center = Geometry.previewPointToDisplayPoint(end, panel: panel,
                                                         display: displayFrame)
        let origin = Geometry.centeredClampedWindowOrigin(size: currentFrame.size,
                                                          center: center,
                                                          bounds: displayFrame)
        WindowMover.move(window: candidate.window, toAppKitOrigin: origin)
    }
}
