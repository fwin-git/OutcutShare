import AppKit

/// Interactive adjust mode for the active region: a transparent overlay on
/// the region's screen. Drag inside the region to move it, drag a corner
/// handle to resize (aspect-locked when `aspect` is given), arrow keys nudge
/// (Shift = 10 pt), mouse-up or Return commits, Esc cancels. The dim overlay
/// underneath follows live via the onChange callback (global AppKit rect).
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
        case resize(anchor: CGPoint) // opposite corner, local coordinates
    }

    private static let handleHitRadius: CGFloat = 12
    private static let handleSize: CGFloat = 9

    private let screenFrame: CGRect
    private var region: CGRect // window-local coordinates
    private let aspect: CGFloat?
    private let onChange: (CGRect) -> Void
    private let onFinish: (_ cancelled: Bool) -> Void
    private var drag: Drag?
    private var finished = false

    init(frame: NSRect, screenFrame: CGRect, region: CGRect, aspect: CGFloat?,
         onChange: @escaping (CGRect) -> Void,
         onFinish: @escaping (_ cancelled: Bool) -> Void) {
        self.screenFrame = screenFrame
        self.region = CGRect(x: region.minX - screenFrame.minX,
                             y: region.minY - screenFrame.minY,
                             width: region.width, height: region.height)
        self.aspect = aspect
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

    private var corners: [CGPoint] {
        [CGPoint(x: region.minX, y: region.minY), CGPoint(x: region.maxX, y: region.minY),
         CGPoint(x: region.minX, y: region.maxY), CGPoint(x: region.maxX, y: region.maxY)]
    }

    private func oppositeCorner(of corner: CGPoint) -> CGPoint {
        CGPoint(x: corner.x == region.minX ? region.maxX : region.minX,
                y: corner.y == region.minY ? region.maxY : region.minY)
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

    override func resetCursorRects() {
        addCursorRect(region, cursor: .openHand)
        for corner in corners {
            let rect = CGRect(x: corner.x - Self.handleHitRadius, y: corner.y - Self.handleHitRadius,
                              width: Self.handleHitRadius * 2, height: Self.handleHitRadius * 2)
            addCursorRect(rect.intersection(bounds), cursor: .crosshair)
        }
    }

    override func keyDown(with event: NSEvent) {
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
        switch event.keyCode {
        case 53: finish(cancelled: true)          // Esc
        case 36, 76: finish(cancelled: false)     // Return / Enter
        case 123: move(to: CGPoint(x: region.minX - step, y: region.minY)) // ←
        case 124: move(to: CGPoint(x: region.minX + step, y: region.minY)) // →
        case 125: move(to: CGPoint(x: region.minX, y: region.minY - step)) // ↓
        case 126: move(to: CGPoint(x: region.minX, y: region.minY + step)) // ↑
        default: super.keyDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        let point = convert(event.locationInWindow, from: nil)
        if let corner = corners.first(where: { hypot($0.x - point.x, $0.y - point.y) <= Self.handleHitRadius }) {
            drag = .resize(anchor: oppositeCorner(of: corner))
        } else if region.contains(point) {
            drag = .move(grabOffset: CGPoint(x: point.x - region.minX, y: point.y - region.minY))
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        switch drag {
        case .move(let grabOffset):
            move(to: CGPoint(x: point.x - grabOffset.x, y: point.y - grabOffset.y))
        case .resize(let anchor):
            let global = Geometry.resizedRegion(anchor: toGlobal(anchor),
                                                dragged: toGlobal(point),
                                                aspect: aspect, screenFrame: screenFrame)
            apply(localRect: toLocal(global))
        case nil:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard drag != nil else { return }
        drag = nil
        finish(cancelled: false)
    }

    override func draw(_ dirtyRect: NSRect) {
        for corner in corners {
            let handle = CGRect(x: corner.x - Self.handleSize / 2,
                                y: corner.y - Self.handleSize / 2,
                                width: Self.handleSize, height: Self.handleSize)
            NSColor.white.setFill()
            NSBezierPath(rect: handle).fill()
            NSColor.black.setStroke()
            let outline = NSBezierPath(rect: handle)
            outline.lineWidth = 1
            outline.stroke()
        }

        let resizeHint = aspect == nil ? "corners resize" : "corners resize (aspect locked)"
        let text = "Drag to move — \(resizeHint) — arrows nudge, Return commits, Esc cancels"
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
