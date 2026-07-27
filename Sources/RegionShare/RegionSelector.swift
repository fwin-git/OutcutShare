import AppKit

struct SelectedRegion {
    /// AppKit global coordinates (bottom-left origin).
    let rect: CGRect
    let screen: NSScreen

    var displayID: CGDirectDisplayID { screen.displayID }
}

/// Front-to-back frames of other apps' normal windows, in AppKit coordinates.
@MainActor
enum WindowCatalog {
    static func otherWindowFrames() -> [CGRect] {
        guard let primary = NSScreen.screens.first,
              let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        let pid = ProcessInfo.processInfo.processIdentifier
        return info.compactMap { entry in
            guard (entry[kCGWindowLayer as String] as? Int) == 0,
                  (entry[kCGWindowOwnerPID as String] as? Int32) != pid,
                  (entry[kCGWindowAlpha as String] as? Double ?? 1) > 0.05,
                  let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let cgRect = CGRect(dictionaryRepresentation: boundsDict),
                  cgRect.width >= 64, cgRect.height >= 64 else {
                return nil
            }
            return Geometry.appKitRect(fromCGTopLeft: cgRect,
                                       primaryHeight: primary.frame.height)
        }
    }
}

/// Full-screen drag-to-select overlay, one window per screen.
/// Esc cancels; a drag smaller than the minimum size is ignored.
/// Modifier UX (Apple screenshot conventions):
///  - Space (idle): toggle window-pick mode — hover highlights a window,
///    click selects its bounds.
///  - Space (while dragging): freeze the selection's size and move it.
///  - Shift (while dragging): lock the current aspect ratio.
///  - Control (while dragging): snap to viewer-friendly sizes, previewed as
///    faded colored rectangles with resolution labels.
@MainActor
final class RegionSelector {
    private var windows: [SelectionWindow] = []
    private var completion: ((SelectedRegion?) -> Void)?

    func begin(completion: @escaping (SelectedRegion?) -> Void) {
        guard windows.isEmpty else {
            completion(nil)
            return
        }
        self.completion = completion
        for screen in NSScreen.screens {
            let window = SelectionWindow(screen: screen, selector: self)
            windows.append(window)
            window.orderFrontRegardless()
        }
        NSApp.activate(ignoringOtherApps: true)
        windows.first?.makeKey()
    }

    func finish(with region: SelectedRegion?) {
        guard let cb = completion else { return }
        completion = nil
        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
        cb(region)
    }
}

private final class SelectionWindow: NSWindow {
    init(screen: NSScreen, selector: RegionSelector) {
        super.init(contentRect: screen.frame, styleMask: .borderless,
                   backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size),
                                    selector: selector)
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        (contentView as? SelectionView)?.cancel()
    }
}

private final class SelectionView: NSView {
    private static let presetSizes: [CGSize] = [
        CGSize(width: 1280, height: 720),
        CGSize(width: 1600, height: 900),
        CGSize(width: 1920, height: 1080),
    ]
    private static let presetColors: [NSColor] = [.systemBlue, .systemGreen, .systemOrange]

    private weak var selector: RegionSelector?
    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?

    // Space / window-pick mode
    private var pickMode = false
    private var windowFramesLocal: [CGRect] = []
    private var hoveredWindow: CGRect?

    // Space while dragging: freeze shape, move it
    private var repositioning = false
    private var lastRepositionPoint: CGPoint?

    // Shift: aspect lock
    private var lockedAspect: CGFloat?

    // Control: preset snapping
    private var presetActive = false
    private var presetCandidates: [CGRect?] = []
    private var snappedPreset: CGRect?

    init(frame: NSRect, selector: RegionSelector) {
        self.selector = selector
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseMoved, .activeAlways],
                                       owner: self, userInfo: nil))
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: pickMode ? .pointingHand : .crosshair)
    }

    func cancel() {
        selector?.finish(with: nil)
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53:
            cancel()
        case 49 where !event.isARepeat: // Space
            if dragStart != nil {
                repositioning = true
                lastRepositionPoint = nil
            } else {
                togglePickMode()
            }
        default:
            super.keyDown(with: event)
        }
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 {
            repositioning = false
            lastRepositionPoint = nil
        } else {
            super.keyUp(with: event)
        }
    }

    private func togglePickMode() {
        pickMode.toggle()
        if pickMode {
            let origin = window?.frame.origin ?? .zero
            windowFramesLocal = WindowCatalog.otherWindowFrames().map {
                $0.offsetBy(dx: -origin.x, dy: -origin.y)
            }
            updateHover(at: mouseLocationInView())
        } else {
            hoveredWindow = nil
        }
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    private func mouseLocationInView() -> CGPoint {
        guard let window else { return .zero }
        return convert(window.mouseLocationOutsideOfEventStream, from: nil)
    }

    private func updateHover(at point: CGPoint) {
        hoveredWindow = Geometry.frontmostWindowFrame(at: point, windows: windowFramesLocal)?
            .intersection(bounds)
        needsDisplay = true
    }

    // MARK: Mouse

    override func mouseMoved(with event: NSEvent) {
        guard pickMode else { return }
        updateHover(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        let point = convert(event.locationInWindow, from: nil)
        if pickMode {
            if let hovered = hoveredWindow, Geometry.meetsMinimumSize(hovered) {
                finish(with: hovered)
            }
            return
        }
        dragStart = point
        dragCurrent = point
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard !pickMode, let start = dragStart else { return }
        let point = convert(event.locationInWindow, from: nil)

        if repositioning {
            let last = lastRepositionPoint ?? point
            var dx = point.x - last.x
            var dy = point.y - last.y
            if let rect = currentSelection() {
                // Keep the frozen selection fully on screen.
                let moved = rect.offsetBy(dx: dx, dy: dy)
                let clamped = Geometry.clampedRegionOrigin(moved.origin, regionSize: rect.size,
                                                           screenFrame: bounds)
                dx = clamped.x - rect.origin.x
                dy = clamped.y - rect.origin.y
            }
            dragStart = CGPoint(x: start.x + dx, y: start.y + dy)
            if let current = dragCurrent {
                dragCurrent = CGPoint(x: current.x + dx, y: current.y + dy)
            }
            snappedPreset = snappedPreset?.offsetBy(dx: dx, dy: dy)
            presetCandidates = presetCandidates.map { $0?.offsetBy(dx: dx, dy: dy) }
            lastRepositionPoint = point
            needsDisplay = true
            return
        }

        dragCurrent = point
        let mods = event.modifierFlags
        presetActive = mods.contains(.control)
        if presetActive {
            presetCandidates = Geometry.presetCandidates(anchor: start, toward: point,
                                                         sizes: Self.presetSizes, bounds: bounds)
            let fitting = presetCandidates.compactMap { $0 }
            if let index = Geometry.snappedPresetIndex(dragged: point, candidates: fitting,
                                                       anchor: start) {
                snappedPreset = fitting[index]
            } else {
                snappedPreset = nil
            }
        } else {
            presetCandidates = []
            snappedPreset = nil
            if mods.contains(.shift) {
                if lockedAspect == nil {
                    let raw = Geometry.selectionRect(from: start, to: point)
                    if raw.width > 8, raw.height > 8 {
                        lockedAspect = raw.width / raw.height
                    }
                }
            } else {
                lockedAspect = nil
            }
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard !pickMode, dragStart != nil else { return }
        let selection = currentSelection()
        dragStart = nil
        dragCurrent = nil
        repositioning = false
        presetActive = false
        lockedAspect = nil
        needsDisplay = true
        guard let selection, Geometry.meetsMinimumSize(selection) else { return }
        finish(with: selection)
    }

    private func finish(with localRect: CGRect) {
        guard let window, let screen = window.screen ?? NSScreen.main else { return }
        let global = window.convertToScreen(localRect).integral
        selector?.finish(with: SelectedRegion(rect: global, screen: screen))
    }

    /// The rect that would be selected right now.
    private func currentSelection() -> CGRect? {
        if pickMode { return hoveredWindow }
        guard let start = dragStart, let current = dragCurrent else { return nil }
        if presetActive, let snapped = snappedPreset { return snapped }
        if let aspect = lockedAspect {
            return Geometry.resizedRegion(anchor: start, dragged: current,
                                          aspect: aspect, screenFrame: bounds)
        }
        return Geometry.selectionRect(from: start, to: current)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let backdrop = NSBezierPath(rect: bounds)
        if let selection = currentSelection() {
            backdrop.append(NSBezierPath(rect: selection))
            backdrop.windingRule = .evenOdd
            NSColor.black.withAlphaComponent(0.25).setFill()
            backdrop.fill()

            NSColor.white.setStroke()
            let outline = NSBezierPath(rect: selection.insetBy(dx: -0.5, dy: -0.5))
            outline.lineWidth = 1
            outline.stroke()

            drawSizeLabel(for: selection)
        } else {
            NSColor.black.withAlphaComponent(0.25).setFill()
            backdrop.fill()
            drawHint()
        }

        if presetActive, let start = dragStart {
            drawPresetPreviews(anchor: start)
        }
    }

    private func drawPresetPreviews(anchor: CGPoint) {
        for (index, candidate) in presetCandidates.enumerated() {
            guard let rect = candidate else { continue }
            let color = Self.presetColors[index % Self.presetColors.count]
            let isSnapped = rect == snappedPreset
            color.withAlphaComponent(isSnapped ? 0.9 : 0.45).setStroke()
            let path = NSBezierPath(rect: rect)
            path.lineWidth = isSnapped ? 3 : 1.5
            if !isSnapped {
                path.setLineDash([6, 4], count: 2, phase: 0)
            }
            path.stroke()

            let size = Self.presetSizes[index]
            let label = "\(Int(size.width)) × \(Int(size.height))"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor.white,
            ]
            let textSize = label.size(withAttributes: attributes)
            // Far corner (away from the anchor), kept inside the rect.
            let x = rect.minX == anchor.x ? rect.maxX - textSize.width - 8 : rect.minX + 8
            let y = rect.minY == anchor.y ? rect.maxY - textSize.height - 6 : rect.minY + 6
            let background = CGRect(x: x - 4, y: y - 2,
                                    width: textSize.width + 8, height: textSize.height + 4)
            color.withAlphaComponent(0.75).setFill()
            NSBezierPath(roundedRect: background, xRadius: 4, yRadius: 4).fill()
            label.draw(at: CGPoint(x: x, y: y), withAttributes: attributes)
        }
    }

    private func drawSizeLabel(for selection: CGRect) {
        let text = "\(Int(selection.width)) × \(Int(selection.height))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attributes)
        let padding: CGFloat = 4
        var origin = CGPoint(x: selection.maxX - size.width - padding,
                             y: selection.minY - size.height - 2 * padding)
        if origin.y < 0 { origin.y = selection.minY + padding }
        let background = CGRect(x: origin.x - padding, y: origin.y - padding / 2,
                                width: size.width + 2 * padding, height: size.height + padding)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: background, xRadius: 4, yRadius: 4).fill()
        text.draw(at: origin, withAttributes: attributes)
    }

    private func drawHint() {
        let text = pickMode
            ? "Click a window to share it — Space returns to drag selection, Esc cancels"
            : "Drag to select — Space picks a window · hold ⇧ locks aspect · hold ⌃ snaps to standard sizes · Esc cancels"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attributes)
        let origin = CGPoint(x: bounds.midX - size.width / 2,
                             y: bounds.maxY * 0.75)
        let background = CGRect(x: origin.x - 12, y: origin.y - 8,
                                width: size.width + 24, height: size.height + 16)
        NSColor.black.withAlphaComponent(0.6).setFill()
        NSBezierPath(roundedRect: background, xRadius: 8, yRadius: 8).fill()
        text.draw(at: origin, withAttributes: attributes)
    }
}
