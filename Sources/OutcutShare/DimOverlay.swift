import AppKit

/// Click-through overlay covering the source display: everything outside the
/// shared region is dimmed, the region itself stays clear. Purely a local
/// visual aid — the window is excluded from capture and the capture is cropped
/// to the region anyway.
@MainActor
final class DimOverlay {
    private let window: NSWindow
    private let screenFrame: CGRect
    private let dimView: DimView

    init(region: CGRect, screen: NSScreen, settings: SettingsStore) {
        screenFrame = screen.frame
        window = NSWindow(contentRect: screen.frame, styleMask: .borderless,
                          backing: .buffered, defer: false)
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        let regionInWindow = CGRect(x: region.minX - screen.frame.minX,
                                    y: region.minY - screen.frame.minY,
                                    width: region.width, height: region.height)
        dimView = DimView(frame: NSRect(origin: .zero, size: screen.frame.size),
                          region: regionInWindow, settings: settings)
        window.contentView = dimView
        window.orderFrontRegardless()
    }

    /// Live-moves the clear cutout (region in AppKit global coordinates).
    func update(region: CGRect) {
        dimView.region = CGRect(x: region.minX - screenFrame.minX,
                                y: region.minY - screenFrame.minY,
                                width: region.width, height: region.height)
    }

    func close() {
        window.orderOut(nil)
    }
}

private final class DimView: NSView {
    var region: CGRect {
        didSet { needsDisplay = true }
    }
    private let settings: SettingsStore
    private var observer: NSObjectProtocol?

    init(frame: NSRect, region: CGRect, settings: SettingsStore) {
        self.region = region
        self.settings = settings
        super.init(frame: frame)
        observer = NotificationCenter.default.addObserver(
            forName: settingsChangedNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.needsDisplay = true
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = min(CGFloat(settings.borderRadius), min(region.width, region.height) / 2)
        if settings.dimmingEnabled && settings.dimOpacity > 0 {
            let path = NSBezierPath(rect: bounds)
            path.append(NSBezierPath(roundedRect: region, xRadius: radius, yRadius: radius))
            path.windingRule = .evenOdd
            NSColor.black.withAlphaComponent(settings.dimOpacity).setFill()
            path.fill()
        }
        if settings.showRegionBorder {
            // Stroke sits fully outside the region so no border pixel could
            // ever reach the captured area; the outer radius is concentric
            // with the cutout's.
            let thickness = CGFloat(settings.borderThickness)
            let outset = thickness / 2 + 1
            let outerRadius = radius > 0 ? radius + outset : 0
            let border = NSBezierPath(roundedRect: region.insetBy(dx: -outset, dy: -outset),
                                      xRadius: outerRadius, yRadius: outerRadius)
            border.lineWidth = thickness
            switch settings.borderStyle {
            case .solid:
                break
            case .dashed:
                border.setLineDash([thickness * 3, thickness * 2], count: 2, phase: 0)
            case .dotted:
                border.lineCapStyle = .round
                border.setLineDash([0.01, thickness * 2.2], count: 2, phase: 0)
            }
            settings.borderColor.setStroke()
            border.stroke()
        }
    }
}
