import AppKit
import IOSurface

/// Floating "what viewers see" preview of the shared output, toggled from
/// the hotbar. Chromeless: no title bar or traffic lights, dragging works
/// anywhere on the picture, edge-resizing keeps the region's aspect ratio.
/// The pin button in the top-left corner lifts the panel above every other
/// window (including the dim overlay); unpinned it stacks like a normal
/// window. Excluded from capture via the app-level filter exclusion.
@MainActor
final class PreviewWindowController: NSObject {
    private let settings: SettingsStore
    private var panel: NSPanel?
    private nonisolated(unsafe) let contentLayer = CALayer()
    private nonisolated(unsafe) var lastSurface: IOSurfaceRef?
    private var privacyLayer: CALayer?
    private var privacyShowing = false
    private var pinButton: NSButton?
    private var aspect: CGFloat = 16.0 / 9.0
    private var screenFrame: CGRect = .zero
    /// Remembers placement while the preview is toggled off mid-session.
    private var lastFrame: CGRect?

    private static let minWidth: CGFloat = 160

    init(settings: SettingsStore) {
        self.settings = settings
    }

    func show(aspect: CGFloat, screen: NSScreen) {
        self.aspect = aspect
        screenFrame = screen.visibleFrame
        if panel == nil {
            build()
        }
        guard let panel else { return }
        let frame = lastFrame.map {
            Geometry.aspectRefittedPanelFrame(current: $0, aspect: aspect,
                                              screenFrame: screenFrame,
                                              minWidth: Self.minWidth)
        } ?? Geometry.previewPanelFrame(aspect: aspect, screenFrame: screenFrame)
        panel.setFrame(frame, display: true)
        applyAspectConstraints()
        applyPinState()
        relayout()
        panel.orderFrontRegardless()
    }

    /// The shared region was resized: refit the panel to the new aspect.
    func aspectChanged(_ aspect: CGFloat) {
        guard self.aspect != aspect else { return }
        self.aspect = aspect
        guard let panel, panel.isVisible else { return }
        panel.setFrame(Geometry.aspectRefittedPanelFrame(current: panel.frame, aspect: aspect,
                                                         screenFrame: screenFrame,
                                                         minWidth: Self.minWidth),
                       display: true)
        applyAspectConstraints()
        relayout()
    }

    func close() {
        if let panel, panel.isVisible {
            lastFrame = panel.frame
        }
        panel?.orderOut(nil)
        hidePrivacyScreen()
    }

    /// Called from the capture sample queue (same pattern as LiveFrameWindow).
    nonisolated func display(surface: IOSurfaceRef) {
        lastSurface = surface
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentLayer.contents = surface
        CATransaction.commit()
    }

    func showPrivacyScreen() {
        privacyShowing = true
        rebuildPrivacyLayer()
    }

    func hidePrivacyScreen() {
        privacyShowing = false
        privacyLayer?.removeFromSuperlayer()
        privacyLayer = nil
    }

    private func rebuildPrivacyLayer() {
        privacyLayer?.removeFromSuperlayer()
        privacyLayer = nil
        guard privacyShowing, let view = panel?.contentView else { return }
        let layer = PrivacyScreenLayer.make(bounds: view.bounds, lastSurface: lastSurface,
                                            contentsScale: panel?.backingScaleFactor ?? 2)
        // Below the pin button's backing layer, above the live picture.
        layer.zPosition = 1
        pinButton?.layer?.zPosition = 2
        view.layer?.addSublayer(layer)
        privacyLayer = layer
    }

    private func build() {
        let contentView = PreviewContentView()
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = 10
        contentView.layer?.masksToBounds = true
        contentView.layer?.backgroundColor = NSColor.black.cgColor
        contentLayer.contentsGravity = .resize
        contentLayer.backgroundColor = NSColor.black.cgColor
        contentView.layer?.addSublayer(contentLayer)
        contentView.onLayout = { [weak self] in self?.relayout() }

        let pin = PinButton()
        pin.bezelStyle = .regularSquare
        pin.isBordered = false
        pin.target = self
        pin.action = #selector(togglePin)
        pin.wantsLayer = true
        pin.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        pin.layer?.cornerRadius = 13
        pin.frame = CGRect(x: 8, y: 0, width: 26, height: 26)
        pin.autoresizingMask = [.minYMargin]
        pin.toolTip = "Keep on top"
        contentView.addSubview(pin)
        pinButton = pin

        let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 320, height: 180),
                            styleMask: [.borderless, .nonactivatingPanel, .resizable],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = contentView
        self.panel = panel
    }

    private func applyAspectConstraints() {
        guard let panel else { return }
        panel.contentAspectRatio = NSSize(width: aspect, height: 1)
        panel.minSize = NSSize(width: Self.minWidth, height: Self.minWidth / aspect)
        panel.maxSize = NSSize(width: screenFrame.width, height: screenFrame.height)
    }

    private func relayout() {
        guard let view = panel?.contentView else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentLayer.frame = view.bounds
        CATransaction.commit()
        pinButton?.frame.origin.y = view.bounds.height - 26 - 8
        rebuildPrivacyLayer()
        applyPinState()
    }

    @objc private func togglePin() {
        settings.previewWindowPinned.toggle()
        applyPinState()
    }

    private func applyPinState() {
        guard let panel else { return }
        let pinned = settings.previewWindowPinned
        // Always above the dim overlay (.screenSaver) — the preview must
        // never be grayed out by our own veil. Pinned raises it one step
        // further, above the hotbar and any other overlay-level window.
        // Level is set here, after all other panel setup: properties like
        // isFloatingPanel silently reset it.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue
                                                + (pinned ? 2 : 1))
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
            .applying(.init(paletteColors: [pinned ? .systemYellow : .white]))
        pinButton?.image = NSImage(systemSymbolName: pinned ? "pin.fill" : "pin",
                                   accessibilityDescription: "Keep on top")?
            .withSymbolConfiguration(config)
    }
}

/// Layout hook + explicit background-drag opt-in for the preview picture.
private final class PreviewContentView: NSView {
    var onLayout: (() -> Void)?

    override var mouseDownCanMoveWindow: Bool { true }
    override func layout() {
        super.layout()
        onLayout?()
    }
}

/// First click must act even while another app is active (the panel never
/// activates the app).
private final class PinButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
}
