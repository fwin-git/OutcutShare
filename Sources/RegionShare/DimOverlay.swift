import AppKit

/// Click-through overlay covering the source display: everything outside the
/// shared region is dimmed, the region itself stays clear. Purely a local
/// visual aid — the window is excluded from capture and the capture is cropped
/// to the region anyway.
@MainActor
final class DimOverlay {
    private let window: NSWindow

    init(region: CGRect, screen: NSScreen, settings: SettingsStore) {
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
        window.contentView = DimView(frame: NSRect(origin: .zero, size: screen.frame.size),
                                     region: regionInWindow, settings: settings)
        window.orderFrontRegardless()
    }

    func close() {
        window.orderOut(nil)
    }
}

private final class DimView: NSView {
    private let region: CGRect
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
        if settings.dimmingEnabled && settings.dimOpacity > 0 {
            let path = NSBezierPath(rect: bounds)
            path.append(NSBezierPath(rect: region))
            path.windingRule = .evenOdd
            NSColor.black.withAlphaComponent(settings.dimOpacity).setFill()
            path.fill()
        }
        if settings.showRegionBorder {
            // Stroke sits fully outside the region so no border pixel could
            // ever reach the captured area.
            let border = NSBezierPath(rect: region.insetBy(dx: -2, dy: -2))
            border.lineWidth = 3
            NSColor.controlAccentColor.setStroke()
            border.stroke()
        }
    }
}
