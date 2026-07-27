import AppKit

/// Interactive adjust mode for the active region: a transparent overlay on
/// the region's screen. Drag inside the region to move it; drag corners (and,
/// in free-resize mode, edges) to resize. Modifiers mirror the selection
/// overlay: Shift locks the aspect, Control snaps to viewer-friendly sizes
/// with previews, Space freezes the shape mid-resize and moves it. Arrow keys
/// nudge (Shift = 10 pt), mouse-up or Return commits, Esc cancels.
@MainActor
final class RegionMover {
    private var window: MoverWindow?
    private var onEnd: ((_ cancelled: Bool) -> Void)?

    func begin(region: CGRect, screen: NSScreen, aspect: CGFloat?,
               onChange: @escaping (CGRect) -> Void,
               onEnd: @escaping (_ cancelled: Bool) -> Void) {
        guard window == nil else {
            onEnd(true)
            return
        }
        self.onEnd = onEnd
        let window = MoverWindow(screen: screen, region: region, aspect: aspect,
                                 onChange: onChange) { [weak self] cancelled in
            self?.finish(cancelled: cancelled)
        }
        self.window = window
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKey()
    }

    func close() {
        finish(cancelled: true)
    }

    private func finish(cancelled: Bool) {
        guard let onEnd else { return }
        self.onEnd = nil
        window?.orderOut(nil)
        window = nil
        onEnd(cancelled)
    }
}

private final class MoverWindow: NSWindow {
    init(screen: NSScreen, region: CGRect, aspect: CGFloat?,
         onChange: @escaping (CGRect) -> Void,
         onFinish: @escaping (_ cancelled: Bool) -> Void) {
        super.init(contentRect: screen.frame, styleMask: .borderless,
                   backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        acceptsMouseMovedEvents = true
        // See SelectionWindow: disables per-pixel alpha click-through.
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = AdjustView(frame: NSRect(origin: .zero, size: screen.frame.size),
                                 screenFrame: screen.frame, region: region, aspect: aspect,
                                 onChange: onChange, onFinish: onFinish)
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        (contentView as? AdjustView)?.finish(cancelled: true)
    }
}

private final class AdjustView: NSView {
    private enum Drag {
        case move(grabOffset: CGPoint)
        case resizeCorner(anchor: CGPoint) // fixed opposite corner
        case resizeEdge(Geometry.RegionEdge)
    }

    private static let cornerHitRadius: CGFloat = 18
    private static let edgeHitBand: CGFloat = 14
    private static let handleSize: CGFloat = 9

    private let screenFrame: CGRect
    private var region: CGRect // window-local coordinates
    /// Session-level aspect lock (virtual display mode); nil = free resize.
    private let sessionAspect: CGFloat?
    private let onChange: (CGRect) -> Void
    private let onFinish: (_ cancelled: Bool) -> Void
    private var drag: Drag?
    private var finished = false

    // Space while dragging: freeze the shape, move it
    private var frozenMove = false
    private var lastFreezePoint: CGPoint?

    // Shift: aspect lock (free mode only; captured at first shift press)
    private var shiftAspect: CGFloat?

    // Control: preset snapping (free mode, corner drags)
    private var presetActive = false
    private var presetCandidates: [CGRect?] = []
    private var snappedPreset: CGRect?
    private var presetAnchor: CGPoint?

    // Space (idle): window-pick mode, like the selection overlay
    private var pickMode = false
    private var windowFramesLocal: [CGRect] = []
    private var hoveredWindow: CGRect?

    private var freeResize: Bool { sessionAspect == nil }

    init(frame: NSRect, screenFrame: CGRect, region: CGRect, aspect: CGFloat?,
         onChange: @escaping (CGRect) -> Void,
         onFinish: @escaping (_ cancelled: Bool) -> Void) {
        self.screenFrame = screenFrame
        self.region = CGRect(x: region.minX - screenFrame.minX,
                             y: region.minY - screenFrame.minY,
                             width: region.width, height: region.height)
        self.sessionAspect = aspect
        self.onChange = onChange
        self.onFinish = onFinish
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var acceptsFirstResponder: Bool { true }

    /// First click must reach the view even while the app isn't active.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func finish(cancelled: Bool) {
        guard !finished else { return }
        finished = true
        onFinish(cancelled)
    }

    // MARK: Geometry helpers

    private var corners: [CGPoint] {
        [CGPoint(x: region.minX, y: region.minY), CGPoint(x: region.maxX, y: region.minY),
         CGPoint(x: region.minX, y: region.maxY), CGPoint(x: region.maxX, y: region.maxY)]
    }

    private var edgeMidpoints: [(edge: Geometry.RegionEdge, point: CGPoint)] {
        [(.left, CGPoint(x: region.minX, y: region.midY)),
         (.right, CGPoint(x: region.maxX, y: region.midY)),
         (.top, CGPoint(x: region.midX, y: region.maxY)),
         (.bottom, CGPoint(x: region.midX, y: region.minY))]
    }

    private func oppositeCorner(of corner: CGPoint) -> CGPoint {
        CGPoint(x: corner.x == region.minX ? region.maxX : region.minX,
                y: corner.y == region.minY ? region.maxY : region.minY)
    }

    private func edgeHit(at point: CGPoint) -> Geometry.RegionEdge? {
        let band = Self.edgeHitBand
        let withinY = point.y >= region.minY - band && point.y <= region.maxY + band
        let withinX = point.x >= region.minX - band && point.x <= region.maxX + band
        if abs(point.x - region.minX) <= band && withinY { return .left }
        if abs(point.x - region.maxX) <= band && withinY { return .right }
        if abs(point.y - region.maxY) <= band && withinX { return .top }
        if abs(point.y - region.minY) <= band && withinX { return .bottom }
        return nil
    }

    private func apply(localRect: CGRect) {
        region = localRect
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
        onChange(CGRect(x: localRect.minX + screenFrame.minX,
                        y: localRect.minY + screenFrame.minY,
                        width: localRect.width, height: localRect.height))
    }

    private func toGlobal(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x + screenFrame.minX, y: p.y + screenFrame.minY)
    }

    private func toLocal(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX - screenFrame.minX, y: r.minY - screenFrame.minY,
               width: r.width, height: r.height)
    }

    private func move(to localOrigin: CGPoint) {
        let clamped = Geometry.clampedRegionOrigin(toGlobal(localOrigin),
                                                   regionSize: region.size,
                                                   screenFrame: screenFrame)
        apply(localRect: CGRect(origin: CGPoint(x: clamped.x - screenFrame.minX,
                                                y: clamped.y - screenFrame.minY),
                                size: region.size))
    }

    // MARK: Window picking

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseMoved, .activeAlways],
                                       owner: self, userInfo: nil))
    }

    private func togglePickMode() {
        pickMode.toggle()
        if pickMode {
            let origin = window?.frame.origin ?? .zero
            windowFramesLocal = WindowCatalog.otherWindowFrames().map {
                $0.offsetBy(dx: -origin.x, dy: -origin.y)
            }
            if let window {
                updateHover(at: convert(window.mouseLocationOutsideOfEventStream, from: nil))
            }
        } else {
            hoveredWindow = nil
        }
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    private func updateHover(at point: CGPoint) {
        hoveredWindow = Geometry.frontmostWindowFrame(at: point, windows: windowFramesLocal)?
            .intersection(bounds)
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        if window?.isKeyWindow == false {
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKey()
        }
        guard pickMode else { return }
        updateHover(at: convert(event.locationInWindow, from: nil))
    }

    // MARK: Cursor & keyboard

    override func resetCursorRects() {
        if pickMode {
            addCursorRect(bounds, cursor: .pointingHand)
            return
        }
        addCursorRect(region, cursor: .openHand)
        if freeResize {
            for (edge, midpoint) in edgeMidpoints {
                let rect = CGRect(x: midpoint.x - Self.edgeHitBand, y: midpoint.y - Self.edgeHitBand,
                                  width: Self.edgeHitBand * 2, height: Self.edgeHitBand * 2)
                let cursor: NSCursor
                switch edge {
                case .left, .right: cursor = .resizeLeftRight
                case .top, .bottom: cursor = .resizeUpDown
                }
                addCursorRect(rect.intersection(bounds), cursor: cursor)
            }
        }
        for corner in corners {
            let rect = CGRect(x: corner.x - Self.cornerHitRadius, y: corner.y - Self.cornerHitRadius,
                              width: Self.cornerHitRadius * 2, height: Self.cornerHitRadius * 2)
            addCursorRect(rect.intersection(bounds), cursor: .crosshair)
        }
    }

    override func keyDown(with event: NSEvent) {
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
        switch event.keyCode {
        case 53: finish(cancelled: true)          // Esc
        case 36, 76: finish(cancelled: false)     // Return / Enter
        case 49: // Space — swallow repeats too, or macOS beeps on each one
            guard !event.isARepeat else { return }
            if drag != nil {
                frozenMove = true
                lastFreezePoint = nil
            } else {
                togglePickMode()
            }
        case 123: move(to: CGPoint(x: region.minX - step, y: region.minY)) // ←
        case 124: move(to: CGPoint(x: region.minX + step, y: region.minY)) // →
        case 125: move(to: CGPoint(x: region.minX, y: region.minY - step)) // ↓
        case 126: move(to: CGPoint(x: region.minX, y: region.minY + step)) // ↑
        default: super.keyDown(with: event)
        }
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 {
            frozenMove = false
            lastFreezePoint = nil
        } else {
            super.keyUp(with: event)
        }
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        let point = convert(event.locationInWindow, from: nil)
        if pickMode {
            updateHover(at: point)
            if let hovered = hoveredWindow, Geometry.meetsMinimumSize(hovered) {
                // Fit the window's bounds (honoring a session aspect lock),
                // apply it live and commit the adjustment.
                let fitted = Geometry.aspectFittedRect(around: toGlobalRect(hovered),
                                                       aspect: sessionAspect,
                                                       screenFrame: screenFrame)
                apply(localRect: toLocal(fitted))
                finish(cancelled: false)
            }
            return
        }
        if let corner = corners.first(where: {
            hypot($0.x - point.x, $0.y - point.y) <= Self.cornerHitRadius
        }) {
            drag = .resizeCorner(anchor: oppositeCorner(of: corner))
        } else if freeResize, let edge = edgeHit(at: point) {
            drag = .resizeEdge(edge)
        } else if region.contains(point) {
            drag = .move(grabOffset: CGPoint(x: point.x - region.minX, y: point.y - region.minY))
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let drag else { return }

        if frozenMove {
            translateFrozen(to: point)
            return
        }

        let mods = event.modifierFlags
        switch drag {
        case .move(let grabOffset):
            move(to: CGPoint(x: point.x - grabOffset.x, y: point.y - grabOffset.y))
        case .resizeCorner(let anchor):
            resizeCorner(anchor: anchor, dragged: point, modifiers: mods)
        case .resizeEdge(let edge):
            updateShiftAspect(modifiers: mods)
            let resized = Geometry.edgeResizedRegion(toGlobalRect(region), edge: edge,
                                                     draggedTo: toGlobal(point),
                                                     lockedAspect: shiftAspect,
                                                     screenFrame: screenFrame)
            apply(localRect: toLocal(resized))
        }
    }

    private func resizeCorner(anchor: CGPoint, dragged: CGPoint, modifiers: NSEvent.ModifierFlags) {
        presetActive = freeResize && modifiers.contains(.control)
        if presetActive {
            presetAnchor = anchor
            presetCandidates = Geometry.presetCandidates(anchor: anchor, toward: dragged,
                                                         sizes: SnapPresets.sizes, bounds: bounds)
            let fitting = presetCandidates.compactMap { $0 }
            if let index = Geometry.snappedPresetIndex(dragged: dragged, candidates: fitting,
                                                       anchor: anchor) {
                snappedPreset = fitting[index]
                apply(localRect: fitting[index])
            }
            needsDisplay = true
            return
        }
        snappedPreset = nil
        presetCandidates = []
        updateShiftAspect(modifiers: modifiers)
        let aspect = sessionAspect ?? shiftAspect
        let global = Geometry.resizedRegion(anchor: toGlobal(anchor), dragged: toGlobal(dragged),
                                            aspect: aspect, screenFrame: screenFrame)
        apply(localRect: toLocal(global))
    }

    private func updateShiftAspect(modifiers: NSEvent.ModifierFlags) {
        guard freeResize else { return }
        if modifiers.contains(.shift) {
            if shiftAspect == nil, region.height > 0 {
                shiftAspect = region.width / region.height
            }
        } else {
            shiftAspect = nil
        }
    }

    private func translateFrozen(to point: CGPoint) {
        let last = lastFreezePoint ?? point
        var dx = point.x - last.x
        var dy = point.y - last.y
        let moved = region.offsetBy(dx: dx, dy: dy)
        let clamped = Geometry.clampedRegionOrigin(toGlobal(moved.origin), regionSize: region.size,
                                                   screenFrame: screenFrame)
        dx = clamped.x - screenFrame.minX - region.origin.x
        dy = clamped.y - screenFrame.minY - region.origin.y
        if case .resizeCorner(let anchor) = drag {
            drag = .resizeCorner(anchor: CGPoint(x: anchor.x + dx, y: anchor.y + dy))
        }
        snappedPreset = snappedPreset?.offsetBy(dx: dx, dy: dy)
        presetCandidates = presetCandidates.map { $0?.offsetBy(dx: dx, dy: dy) }
        presetAnchor = presetAnchor.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
        lastFreezePoint = point
        apply(localRect: region.offsetBy(dx: dx, dy: dy))
    }

    private func toGlobalRect(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX + screenFrame.minX, y: r.minY + screenFrame.minY,
               width: r.width, height: r.height)
    }

    override func mouseUp(with event: NSEvent) {
        guard drag != nil else { return }
        drag = nil
        frozenMove = false
        presetActive = false
        shiftAspect = nil
        finish(cancelled: false)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        // Invisible floor: keeps the fully transparent interior clickable.
        NSColor.black.withAlphaComponent(0.01).setFill()
        bounds.fill()

        if pickMode {
            let backdrop = NSBezierPath(rect: bounds)
            if let hovered = hoveredWindow {
                backdrop.append(NSBezierPath(rect: hovered))
                backdrop.windingRule = .evenOdd
            }
            NSColor.black.withAlphaComponent(0.25).setFill()
            backdrop.fill()
            if let hovered = hoveredWindow {
                NSColor.white.setStroke()
                let outline = NSBezierPath(rect: hovered.insetBy(dx: -0.5, dy: -0.5))
                outline.lineWidth = 1
                outline.stroke()
            }
            drawHint("Click a window to snap the region to it — Space returns, Esc cancels")
            return
        }

        var handles = corners
        if freeResize {
            handles += edgeMidpoints.map(\.point)
        }
        for handle in handles {
            let rect = CGRect(x: handle.x - Self.handleSize / 2,
                              y: handle.y - Self.handleSize / 2,
                              width: Self.handleSize, height: Self.handleSize)
            NSColor.white.setFill()
            NSBezierPath(rect: rect).fill()
            NSColor.black.setStroke()
            let outline = NSBezierPath(rect: rect)
            outline.lineWidth = 1
            outline.stroke()
        }

        if presetActive, let anchor = presetAnchor {
            SnapPresets.draw(candidates: presetCandidates, snapped: snappedPreset, anchor: anchor)
        }

        let resizeHint = freeResize
            ? "corners & edges resize · ⇧ locks aspect · ⌃ snaps to standard sizes"
            : "corners resize (aspect locked)"
        drawHint("Drag to move — \(resizeHint) · Space picks a window (moves while resizing) · ⏎ commits · ⎋ cancels")
    }

    private func drawHint(_ text: String) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attributes)
        let origin = CGPoint(x: bounds.midX - size.width / 2, y: bounds.maxY * 0.85)
        let background = CGRect(x: origin.x - 12, y: origin.y - 8,
                                width: size.width + 24, height: size.height + 16)
        NSColor.black.withAlphaComponent(0.6).setFill()
        NSBezierPath(roundedRect: background, xRadius: 8, yRadius: 8).fill()
        text.draw(at: origin, withAttributes: attributes)
    }
}
