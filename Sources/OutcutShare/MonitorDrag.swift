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

    /// All normal-layer windows whose center sits inside `area` (front to
    /// back), excluding ours.
    static func windows(in area: CGRect, excludingPID: pid_t) -> [FoundWindow] {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return [] }
        var found: [FoundWindow] = []
        for info in list {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  pid != excludingPID,
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let frame = appKitFrame(fromBoundsDict: info[kCGWindowBounds as String]),
                  area.contains(CGPoint(x: frame.midX, y: frame.midY))
            else { continue }
            found.append(FoundWindow(id: id, pid: pid, frame: frame))
        }
        return found
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

    /// Repositions another app's window (AppKit-global target origin).
    /// Raising switches macOS to the window's Space — the teardown rescue
    /// must NOT raise, or stopping the monitor yanks the user to another
    /// Space. Returns false when the AX window can't be resolved.
    @discardableResult
    static func move(window: WindowLocator.FoundWindow, toAppKitOrigin origin: CGPoint,
                     raise: Bool = true) -> Bool {
        guard let currentFrame = WindowLocator.frame(ofWindow: window.id),
              let axWindow = axWindow(for: window, frame: currentFrame) else { return false }
        setPosition(axWindow, appKitOrigin: origin, size: currentFrame.size)
        if raise {
            AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
        }
        return true
    }

    /// Resolves the AX element once so repeated per-drag-event moves stay
    /// cheap (no window-list walks per event).
    static func resolveAXWindow(for window: WindowLocator.FoundWindow) -> AXUIElement? {
        guard let currentFrame = WindowLocator.frame(ofWindow: window.id) else { return nil }
        return axWindow(for: window, frame: currentFrame)
    }

    static func setPosition(_ axWindow: AXUIElement, appKitOrigin origin: CGPoint,
                            size: CGSize) {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        var point = Geometry.cgTopLeftPoint(forAppKit: CGRect(origin: origin, size: size),
                                            primaryHeight: primaryHeight)
        if let value = AXValueCreate(.cgPoint, &point) {
            AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, value)
        }
    }

    /// Position + size in one go (snap tiles).
    static func setFrame(_ axWindow: AXUIElement, appKitFrame frame: CGRect) {
        setPosition(axWindow, appKitOrigin: frame.origin, size: frame.size)
        var size = frame.size
        if let value = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(axWindow, kAXSizeAttribute as CFString, value)
        }
        // Resizing anchors the top-left; re-apply the position so the frame
        // lands exactly where the tile is.
        setPosition(axWindow, appKitOrigin: frame.origin, size: frame.size)
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

/// Brings every window home from the virtual display when it's torn down:
/// macOS leaves windows of a disconnected virtual display at stale
/// coordinates (no migration), so they'd be lost off-screen otherwise.
/// The moves run AFTER the display is destroyed — moving them while the
/// display still existed attached them to the wrong Space; once the
/// display dies, macOS adopts them onto the CURRENT Space and our delayed
/// move only fixes their coordinates.
@MainActor
enum MonitorWindowRescue {
    typealias Plan = [(window: WindowLocator.FoundWindow, origin: CGPoint)]

    /// Capture the window list and targets while the display still exists.
    static func plan(from displayFrame: CGRect, to target: CGRect) -> Plan {
        guard WindowMover.hasPermission else { return [] }
        return WindowLocator.windows(in: displayFrame, excludingPID: getpid()).map {
            ($0, Geometry.rehomedWindowOrigin(window: $0.frame,
                                              display: displayFrame, target: target))
        }
    }

    /// Execute after the display is gone and the window server settled.
    static func execute(_ plan: Plan) {
        for entry in plan {
            WindowMover.move(window: entry.window, toAppKitOrigin: entry.origin,
                             raise: false)
        }
    }
}

/// Direct manipulation of the virtual monitor's windows through the preview
/// picture: grab a rendered window to move it (magnet-style snap zones at
/// the edges), or drag it off the panel to pop it back onto the real
/// screen. Fed by the preview content view's mouse events (view-local
/// points with the current bounds).
@MainActor
final class MonitorWindowManipulator {
    private weak var session: ShareSession?
    private let displayFrame: CGRect
    private weak var preview: PreviewWindowController?
    private let settings: SettingsStore
    private var drag: (window: WindowLocator.FoundWindow, ax: AXUIElement,
                       grabOffset: CGSize, startLocal: CGPoint, started: Bool)?
    private var lastMoveTime: TimeInterval = 0
    private var promptedForPermission = false

    init(session: ShareSession, displayFrame: CGRect, preview: PreviewWindowController,
         settings: SettingsStore = .shared) {
        self.session = session
        self.displayFrame = displayFrame
        self.preview = preview
        self.settings = settings
    }

    /// The configurable "pull the window out" modifier is held right now.
    private var pullOutHeld: Bool {
        NSEvent.modifierFlags.contains(settings.dragOutModifier.flag)
    }

    /// The physical screen windows pop out to. NEVER NSScreen.main — that's
    /// the key window's screen, which becomes the VIRTUAL display as soon
    /// as a window over there gains focus (pull-out then silently moved
    /// windows "out" onto the monitor itself, i.e. nowhere).
    private var popOutScreen: NSScreen? {
        if let panelFrame = preview?.panelFrame,
           let screen = NSScreen.screens.first(where: { $0.frame.intersects(panelFrame) }) {
            return screen
        }
        return NSScreen.screens.first
    }

    /// Returns false when no window sits under the point — the caller then
    /// treats the press as a panel-background drag.
    @discardableResult
    func mouseDown(at local: CGPoint, in bounds: CGRect) -> Bool {
        drag = nil
        let displayPoint = Geometry.previewPointToDisplayPoint(
            local, panel: CGRect(origin: .zero, size: bounds.size), display: displayFrame)
        guard let found = WindowLocator.frontmostWindow(at: displayPoint,
                                                       excludingPID: getpid()) else {
            return false
        }
        guard WindowMover.hasPermission else {
            if !promptedForPermission {
                promptedForPermission = true
                WindowMover.requestPermission()
                session?.onPermissionsNeeded?()
            }
            return true
        }
        guard let ax = WindowMover.resolveAXWindow(for: found) else { return true }
        let offset = CGSize(width: found.frame.minX - displayPoint.x,
                            height: found.frame.minY - displayPoint.y)
        drag = (found, ax, offset, local, false)
        return true
    }

    func mouseDragged(to local: CGPoint, in bounds: CGRect) {
        guard var drag else { return }
        if !drag.started {
            guard hypot(local.x - drag.startLocal.x, local.y - drag.startLocal.y) > 6 else {
                return
            }
            drag.started = true
        }
        self.drag = drag
        preview?.showPullOutHint(pullOutHeld)
        // Modifier drags never move the real window mid-drag — a ghost
        // thumbnail rides the cursor instead (across the boundary too), and
        // the drop decides. Snapping is off so edge drags can't collide
        // with the pull-out gesture.
        if pullOutHeld {
            preview?.showSnapTile(nil)
            preview?.updateDragProxy(windowFrame: drag.window.frame,
                                     grabOffset: drag.grabOffset,
                                     cursor: NSEvent.mouseLocation)
            return
        }
        preview?.endDragProxy()
        guard bounds.contains(local) else {
            // Outside the panel: window stays put until the drop decides.
            preview?.showSnapTile(nil)
            return
        }
        let unit = CGPoint(x: local.x / bounds.width, y: local.y / bounds.height)
        preview?.showSnapTile(Geometry.snapTileUnit(for: unit))
        // Live-follow, throttled to display rate.
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastMoveTime > 1.0 / 60.0 else { return }
        lastMoveTime = now
        let displayPoint = Geometry.previewPointToDisplayPoint(
            local, panel: CGRect(origin: .zero, size: bounds.size), display: displayFrame)
        let origin = Geometry.clampedRegionOrigin(
            CGPoint(x: displayPoint.x + drag.grabOffset.width,
                    y: displayPoint.y + drag.grabOffset.height),
            regionSize: drag.window.frame.size, screenFrame: displayFrame)
        WindowMover.setPosition(drag.ax, appKitOrigin: origin, size: drag.window.frame.size)
    }

    func mouseUp(at local: CGPoint, in bounds: CGRect) {
        defer {
            preview?.showSnapTile(nil)
            preview?.showPullOutHint(false)
            preview?.endDragProxy()
            drag = nil
        }
        guard let drag, drag.started else { return }
        if bounds.contains(local) {
            if pullOutHeld {
                // Modifier drop inside: place the window at the drop point
                // (the ghost carried it — the real window hasn't moved yet).
                let displayPoint = Geometry.previewPointToDisplayPoint(
                    local, panel: CGRect(origin: .zero, size: bounds.size),
                    display: displayFrame)
                let origin = Geometry.clampedRegionOrigin(
                    CGPoint(x: displayPoint.x + drag.grabOffset.width,
                            y: displayPoint.y + drag.grabOffset.height),
                    regionSize: drag.window.frame.size, screenFrame: displayFrame)
                WindowMover.setPosition(drag.ax, appKitOrigin: origin,
                                        size: drag.window.frame.size)
                return
            }
            let unit = CGPoint(x: local.x / bounds.width, y: local.y / bounds.height)
            if let tile = Geometry.snapTileUnit(for: unit) {
                WindowMover.setFrame(drag.ax,
                                     appKitFrame: Geometry.rectByScaling(unit: tile,
                                                                         into: displayFrame))
            }
            return
        }
        // Off the panel: only the pull-out modifier pops the window back to
        // the real screen — a plain drag that strays outside does nothing.
        guard pullOutHeld, let screen = popOutScreen else { return }
        let origin = Geometry.centeredClampedWindowOrigin(size: drag.window.frame.size,
                                                          center: NSEvent.mouseLocation,
                                                          bounds: screen.visibleFrame)
        WindowMover.setPosition(drag.ax, appKitOrigin: origin, size: drag.window.frame.size)
    }
}

/// "Control mode": forwards clicks, drags and scrolls from the preview
/// picture onto the virtual display as synthetic events, so folders and
/// browsers on the monitor can be driven without moving the mouse there.
/// Posting events needs the same Accessibility permission as window
/// moving. The system cursor briefly jumps to the virtual display during a
/// gesture (that's where the event happens — visible in the preview) and
/// returns when the gesture ends.
@MainActor
final class MonitorPointerForwarder {
    private weak var session: ShareSession?
    private let displayFrame: CGRect
    private var promptedForPermission = false

    init(session: ShareSession, displayFrame: CGRect) {
        self.session = session
        self.displayFrame = displayFrame
    }

    /// The injected mouse-down hands the physical tracking to the app under
    /// the synthetic location, so from here the user's mouse drives the
    /// monitor natively — no warp-backs (they fought the user's movement).
    /// The way back is the edge-exit poller on the preview panel.
    func mouseDown(clickCount: Int, at local: CGPoint, in bounds: CGRect,
                   button: CGMouseButton) {
        guard ensurePermission() else { return }
        post(button == .left ? .leftMouseDown : .rightMouseDown,
             at: target(local, bounds), button: button, clickCount: clickCount)
    }

    func mouseDragged(at local: CGPoint, in bounds: CGRect, button: CGMouseButton) {
        guard WindowMover.hasPermission else { return }
        post(button == .left ? .leftMouseDragged : .rightMouseDragged,
             at: target(local, bounds), button: button, clickCount: 1)
    }

    func mouseUp(clickCount: Int, at local: CGPoint, in bounds: CGRect,
                 button: CGMouseButton) {
        guard WindowMover.hasPermission else { return }
        post(button == .left ? .leftMouseUp : .rightMouseUp,
             at: target(local, bounds), button: button, clickCount: clickCount)
    }

    func scroll(deltaX: CGFloat, deltaY: CGFloat, at local: CGPoint, in bounds: CGRect) {
        guard ensurePermission() else { return }
        let point = target(local, bounds)
        let saved = currentCursor()
        CGWarpMouseCursorPosition(point)
        if let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                               wheel1: Int32(deltaY.rounded()),
                               wheel2: Int32(deltaX.rounded()), wheel3: 0) {
            event.location = point
            event.post(tap: .cghidEventTap)
        }
        CGWarpMouseCursorPosition(saved)
    }

    private func target(_ local: CGPoint, _ bounds: CGRect) -> CGPoint {
        let appKit = Geometry.previewPointToDisplayPoint(
            local, panel: CGRect(origin: .zero, size: bounds.size),
            display: displayFrame.insetBy(dx: 1, dy: 1))
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return Geometry.cgPoint(fromAppKit: appKit, primaryHeight: primaryHeight)
    }

    private func currentCursor() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    private func post(_ type: CGEventType, at point: CGPoint, button: CGMouseButton,
                      clickCount: Int) {
        guard let event = CGEvent(mouseEventSource: nil, mouseType: type,
                                  mouseCursorPosition: point, mouseButton: button) else {
            return
        }
        event.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
        event.post(tap: .cghidEventTap)
    }

    private func ensurePermission() -> Bool {
        guard WindowMover.hasPermission else {
            if !promptedForPermission {
                promptedForPermission = true
                WindowMover.requestPermission()
                session?.onPermissionsNeeded?()
            }
            return false
        }
        return true
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
        preview?.lowerBehindDraggedWindow(nil)
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
        guard let candidate, let panel = preview?.panelFrame else { return }
        let over = panel.contains(NSEvent.mouseLocation)
        preview?.setDropTargetHighlight(over)
        // Keep the dragged window visible IN FRONT of the panel so the user
        // sees what they're placing.
        preview?.lowerBehindDraggedWindow(over ? candidate.window.id : nil)
    }

    private func mouseUp() {
        defer {
            preview?.setDropTargetHighlight(false)
            preview?.lowerBehindDraggedWindow(nil)
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
