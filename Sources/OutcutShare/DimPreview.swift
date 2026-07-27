import AppKit

/// Full-screen dim layer shown while the user drags the dim-amount slider:
/// everything dims at the live opacity except a cutout around the settings
/// window, so the value can be judged against real screen content.
@MainActor
final class DimPreview {
    static let shared = DimPreview()

    private var window: NSWindow?
    private var view: PreviewDimView?
    private var hideWork: DispatchWorkItem?

    func begin() {
        hideWork?.cancel()
        hideWork = nil
        let fallback = NSApp.windows.first { $0.isVisible && $0.styleMask.contains(.titled) }
        guard let anchor = NSApp.keyWindow ?? NSApp.mainWindow ?? fallback,
              let screen = anchor.screen ?? NSScreen.main else { return }
        if window == nil || window?.frame.size != screen.frame.size {
            window?.orderOut(nil)
            build(screen: screen)
        }
        guard let window, let view else { return }
        view.cutout = CGRect(x: anchor.frame.minX - screen.frame.minX,
                             y: anchor.frame.minY - screen.frame.minY,
                             width: anchor.frame.width, height: anchor.frame.height)
        window.orderFrontRegardless()
    }

    func end() {
        let work = DispatchWorkItem { [weak self] in
            self?.window?.orderOut(nil)
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private func build(screen: NSScreen) {
        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        let view = PreviewDimView(frame: NSRect(origin: .zero, size: screen.frame.size))
        window.contentView = view
        self.window = window
        self.view = view
    }
}

private final class PreviewDimView: NSView {
    var cutout: CGRect = .zero {
        didSet { needsDisplay = true }
    }
    private var observer: NSObjectProtocol?

    override init(frame: NSRect) {
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
        let settings = SettingsStore.shared
        let path = NSBezierPath(rect: bounds)
        path.append(NSBezierPath(roundedRect: cutout.insetBy(dx: -6, dy: -6),
                                 xRadius: 14, yRadius: 14))
        path.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(settings.dimmingEnabled ? settings.dimOpacity : 0)
            .setFill()
        path.fill()
    }
}
