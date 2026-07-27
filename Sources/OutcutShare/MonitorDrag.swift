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
        setPosition(axWindow, appKitOrigin: origin, size: currentFrame.size)
        AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
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

    func mouseDown(at local: CGPoint, in bounds: CGRect) {
        drag = nil
        let displayPoint = Geometry.previewPointToDisplayPoint(
            local, panel: CGRect(origin: .zero, size: bounds.size), display: displayFrame)
        guard let found = WindowLocator.frontmostWindow(at: displayPoint,
                                                       excludingPID: getpid()) else { return }
        guard WindowMover.hasPermission else {
            if !promptedForPermission {
                promptedForPermission = true
                WindowMover.requestPermission()
                session?.onPermissionsNeeded?()
            }
            return
        }
        guard let ax = WindowMover.resolveAXWindow(for: found) else { return }
        let offset = CGSize(width: found.frame.minX - displayPoint.x,
                            height: found.frame.minY - displayPoint.y)
        drag = (found, ax, offset, local, false)
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
        guard bounds.contains(local) else {
            // Outside the panel: window stays put until the drop decides.
            preview?.showSnapTile(nil)
            return
        }
        // Holding the pull-out modifier disables snapping so edge drags
        // can't collide with the "drag it out" gesture.
        if pullOutHeld {
            preview?.showSnapTile(nil)
        } else {
            let unit = CGPoint(x: local.x / bounds.width, y: local.y / bounds.height)
            preview?.showSnapTile(Geometry.snapTileUnit(for: unit))
        }
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
            drag = nil
        }
        guard let drag, drag.started else { return }
        if bounds.contains(local) {
            guard !pullOutHeld else { return } // modifier: free placement, no snap
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
    private var savedCursor: CGPoint?
    private var promptedForPermission = false
    private var upMonitors: [Any] = []
    /// True from mouse-down until the warp-back completed — the stranded-
    /// cursor watchdog must not fight an in-flight gesture.
    private(set) var gestureActive = false

    init(session: ShareSession, displayFrame: CGRect) {
        self.session = session
        self.displayFrame = displayFrame
    }

    deinit {
        for monitor in upMonitors {
            NSEvent.removeMonitor(monitor)
        }
    }

    func mouseDown(clickCount: Int, at local: CGPoint, in bounds: CGRect,
                   button: CGMouseButton) {
        guard ensurePermission() else { return }
        gestureActive = true
        savedCursor = currentCursor()
        post(button == .left ? .leftMouseDown : .rightMouseDown,
             at: target(local, bounds), button: button, clickCount: clickCount)
        // The injected mouse-down makes the window server hand the physical
        // drag/up tracking to the app under the SYNTHETIC location — our
        // view then never receives the mouse-up, which used to leave the
        // gesture (and the cursor) stranded on the virtual display. A
        // global monitor sees that other app's mouse-up and finalizes.
        installUpMonitor()
    }

    func mouseDragged(at local: CGPoint, in bounds: CGRect, button: CGMouseButton) {
        guard WindowMover.hasPermission, gestureActive else { return }
        post(button == .left ? .leftMouseDragged : .rightMouseDragged,
             at: target(local, bounds), button: button, clickCount: 1)
    }

    func mouseUp(clickCount: Int, at local: CGPoint, in bounds: CGRect,
                 button: CGMouseButton) {
        guard WindowMover.hasPermission, gestureActive else { return }
        post(button == .left ? .leftMouseUp : .rightMouseUp,
             at: target(local, bounds), button: button, clickCount: clickCount)
        finalizeGesture()
    }

    private func installUpMonitor() {
        removeUpMonitors()
        let monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseUp, .rightMouseUp],
            handler: { [weak self] _ in
                MainActor.assumeIsolated { self?.finalizeGesture() }
            })
        if let monitor {
            upMonitors.append(monitor)
        }
    }

    private func removeUpMonitors() {
        upMonitors.forEach { NSEvent.removeMonitor($0) }
        upMonitors = []
    }

    /// Ends the gesture from whichever side saw the mouse-up (our view or
    /// the target app via the global monitor). The warp-back runs as a
    /// short burst: queued synthetic events carry the monitor position and
    /// would undo a single immediate warp.
    private func finalizeGesture() {
        guard gestureActive else { return }
        removeUpMonitors()
        let saved = savedCursor
        savedCursor = nil
        if let saved {
            for delay in [0.08, 0.22, 0.4] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    CGWarpMouseCursorPosition(saved)
                    CGAssociateMouseAndMouseCursorPosition(1)
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            MainActor.assumeIsolated { self?.gestureActive = false }
        }
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
