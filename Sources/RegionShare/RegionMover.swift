import AppKit

/// Interactive move mode for the active region: a transparent overlay on the
/// region's screen. Drag the region to reposition it, arrow keys nudge
/// (Shift = 10 pt), mouse-up or Return commits, Esc cancels. The dim overlay
/// underneath follows live via the onChange callback.
@MainActor
final class RegionMover {
    private var window: MoverWindow?
    private var onEnd: ((_ cancelled: Bool) -> Void)?

    func begin(region: CGRect, screen: NSScreen,
               onChange: @escaping (CGPoint) -> Void,
               onEnd: @escaping (_ cancelled: Bool) -> Void) {
        guard window == nil else {
            onEnd(true)
            return
        }
        self.onEnd = onEnd
        let window = MoverWindow(screen: screen, region: region, onChange: onChange) { [weak self] cancelled in
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
    init(screen: NSScreen, region: CGRect,
         onChange: @escaping (CGPoint) -> Void,
         onFinish: @escaping (_ cancelled: Bool) -> Void) {
        super.init(contentRect: screen.frame, styleMask: .borderless,
                   backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = MoveView(frame: NSRect(origin: .zero, size: screen.frame.size),
                               screenFrame: screen.frame, region: region,
                               onChange: onChange, onFinish: onFinish)
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        (contentView as? MoveView)?.finish(cancelled: true)
    }
}

private final class MoveView: NSView {
    private let screenFrame: CGRect
    private var region: CGRect // window-local coordinates
    private let onChange: (CGPoint) -> Void
    private let onFinish: (_ cancelled: Bool) -> Void
    private var grabOffset: CGPoint?
    private var finished = false

    init(frame: NSRect, screenFrame: CGRect, region: CGRect,
         onChange: @escaping (CGPoint) -> Void,
         onFinish: @escaping (_ cancelled: Bool) -> Void) {
        self.screenFrame = screenFrame
        self.region = CGRect(x: region.minX - screenFrame.minX,
                             y: region.minY - screenFrame.minY,
                             width: region.width, height: region.height)
        self.onChange = onChange
        self.onFinish = onFinish
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var acceptsFirstResponder: Bool { true }

    func finish(cancelled: Bool) {
        guard !finished else { return }
        finished = true
        onFinish(cancelled)
    }

    private func move(to localOrigin: CGPoint) {
        let clamped = Geometry.clampedRegionOrigin(
            CGPoint(x: localOrigin.x + screenFrame.minX, y: localOrigin.y + screenFrame.minY),
            regionSize: region.size, screenFrame: screenFrame)
        region.origin = CGPoint(x: clamped.x - screenFrame.minX, y: clamped.y - screenFrame.minY)
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
        onChange(clamped)
    }

    override func resetCursorRects() {
        addCursorRect(region, cursor: grabOffset == nil ? .openHand : .closedHand)
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
        guard region.contains(point) else { return }
        grabOffset = CGPoint(x: point.x - region.minX, y: point.y - region.minY)
        window?.invalidateCursorRects(for: self)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let grabOffset else { return }
        let point = convert(event.locationInWindow, from: nil)
        move(to: CGPoint(x: point.x - grabOffset.x, y: point.y - grabOffset.y))
    }

    override func mouseUp(with event: NSEvent) {
        guard grabOffset != nil else { return }
        grabOffset = nil
        finish(cancelled: false)
    }

    override func draw(_ dirtyRect: NSRect) {
        let text = "Drag the region to move it — arrow keys nudge, Return commits, Esc cancels"
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
