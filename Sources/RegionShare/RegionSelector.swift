import AppKit

struct SelectedRegion {
    /// AppKit global coordinates (bottom-left origin).
    let rect: CGRect
    let screen: NSScreen

    var displayID: CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber)?.uint32Value ?? 0
    }
}

/// Full-screen drag-to-select overlay, one window per screen.
/// Esc cancels; a drag smaller than the minimum size is ignored and the
/// overlay stays up for another attempt.
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
    private weak var selector: RegionSelector?
    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?

    init(frame: NSRect, selector: RegionSelector) {
        self.selector = selector
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    func cancel() {
        selector?.finish(with: nil)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            cancel()
        } else {
            super.keyDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        dragStart = convert(event.locationInWindow, from: nil)
        dragCurrent = dragStart
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        dragCurrent = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let start = dragStart, let window = window,
              let screen = window.screen ?? NSScreen.main else { return }
        let end = convert(event.locationInWindow, from: nil)
        let local = Geometry.selectionRect(from: start, to: end)
        dragStart = nil
        dragCurrent = nil
        needsDisplay = true
        guard Geometry.meetsMinimumSize(local) else { return }
        let global = window.convertToScreen(local)
        selector?.finish(with: SelectedRegion(rect: global, screen: screen))
    }

    override func draw(_ dirtyRect: NSRect) {
        let backdrop = NSBezierPath(rect: bounds)
        if let start = dragStart, let current = dragCurrent {
            let selection = Geometry.selectionRect(from: start, to: current)
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
        let text = "Drag to select the region to share — press Esc to cancel"
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
