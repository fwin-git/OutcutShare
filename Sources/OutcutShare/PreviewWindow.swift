import AppKit
import IOSurface

/// Floating "what viewers see" preview of the shared output, toggled from
/// the hotbar or the Companions settings group. Chromeless: no title bar or
/// traffic lights, dragging works anywhere on the picture (the ≡ grabber in
/// the top-left corner is a visual affordance), edge-resizing keeps the
/// region's aspect ratio. The pause button in the top-right corner drives
/// the session's privacy pause — usable even with the hotbar hidden. Docks
/// outside the shared region on show (it's capture-excluded either way, but
/// never locally covers what's being shared) and always floats above the
/// dim overlay.
@MainActor
final class PreviewWindowController: NSObject {
    private weak var session: ShareSession?
    private let settings: SettingsStore
    private var panel: NSPanel?
    private nonisolated(unsafe) let contentLayer = CALayer()
    private nonisolated(unsafe) var lastSurface: IOSurfaceRef?
    private var privacyLayer: CALayer?
    private var privacyShowing = false
    private var dropHighlight: CALayer?
    private var snapTileLayer: CALayer?
    private var grabber: NSImageView?
    private var pauseButton: NSButton?
    private var controlButton: NSButton?
    private var aspect: CGFloat = 16.0 / 9.0
    private var screenFrame: CGRect = .zero
    /// Remembers the user-chosen size while the preview is toggled off.
    private var lastFrame: CGRect?

    private static let minWidth: CGFloat = 160
    private static let cornerControlSize: CGFloat = 26
    private static let cornerMargin: CGFloat = 8

    init(session: ShareSession, settings: SettingsStore) {
        self.session = session
        self.settings = settings
    }

    func show(region: CGRect, screen: NSScreen) {
        aspect = region.width / region.height
        screenFrame = screen.visibleFrame
        if panel == nil {
            build()
        }
        guard let panel else { return }
        let width = min(max(lastFrame?.width ?? 320, Self.minWidth), screenFrame.width)
        var size = CGSize(width: width, height: width / aspect)
        if size.height > screenFrame.height {
            size.height = screenFrame.height
            size.width = size.height * aspect
        }
        panel.setFrame(Geometry.previewDockedFrame(size: size, region: region,
                                                   screenFrame: screenFrame),
                       display: true)
        applyAspectConstraints()
        relayout()
        refresh()
        panel.orderFrontRegardless()
    }

    /// Virtual-monitor mode: the preview is the primary way to see the
    /// otherwise invisible screen — large and centered instead of docked.
    func showProminent(aspect: CGFloat, screen: NSScreen) {
        self.aspect = aspect
        screenFrame = screen.visibleFrame
        if panel == nil {
            build()
        }
        guard let panel else { return }
        panel.setFrame(Geometry.prominentPreviewFrame(aspect: aspect,
                                                      screenFrame: screenFrame),
                       display: true)
        applyAspectConstraints()
        relayout()
        refresh()
        panel.orderFrontRegardless()
    }

    /// Current on-screen frame (nil while hidden) — used to anchor the
    /// hotbar next to the panel in virtual-monitor mode.
    var panelFrame: CGRect? {
        guard let panel, panel.isVisible else { return nil }
        return panel.frame
    }

    /// The shared region was resized: refit the panel (in place) to the new
    /// aspect.
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

    /// Syncs the pause button with the session state (called via notifyUI).
    func refresh() {
        let paused = session?.isPaused ?? false
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            .applying(.init(paletteColors: [paused ? .systemYellow : .white]))
        pauseButton?.image = NSImage(systemSymbolName: paused ? "play.fill" : "pause.fill",
                                     accessibilityDescription: paused ? "Resume sharing"
                                                                      : "Pause sharing")?
            .withSymbolConfiguration(config)
        pauseButton?.toolTip = paused ? "Resume sharing" : "Pause sharing"
    }

    /// Called from the capture sample queue (same pattern as LiveFrameWindow).
    nonisolated func display(surface: IOSurfaceRef) {
        lastSurface = surface
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentLayer.contents = surface
        CATransaction.commit()
    }

    /// Virtual-monitor mode: picture drags manage the monitor's windows,
    /// and the control-mode button (clicks pass through) appears.
    func configureMonitorInteraction(manipulator: MonitorWindowManipulator,
                                     forwarder: MonitorPointerForwarder) {
        if panel == nil {
            build()
        }
        guard let view = panel?.contentView as? PreviewContentView else { return }
        view.interactionHandler = manipulator
        view.pointerForwarder = forwarder
        view.passthroughActive = false
        controlButton?.isHidden = false
        updateControlButton()
    }

    func clearMonitorInteraction() {
        guard let view = panel?.contentView as? PreviewContentView else { return }
        view.interactionHandler = nil
        view.pointerForwarder = nil
        view.passthroughActive = false
        controlButton?.isHidden = true
        showSnapTile(nil)
    }

    /// Highlights a magnet snap zone (unit rect, y up) during a window drag.
    func showSnapTile(_ unit: CGRect?) {
        snapTileLayer?.removeFromSuperlayer()
        snapTileLayer = nil
        guard let unit, let view = panel?.contentView else { return }
        let layer = CALayer()
        layer.frame = Geometry.rectByScaling(unit: unit, into: view.bounds).insetBy(dx: 3, dy: 3)
        layer.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.25).cgColor
        layer.borderColor = NSColor.controlAccentColor.cgColor
        layer.borderWidth = 2
        layer.cornerRadius = 6
        layer.zPosition = 3
        view.layer?.addSublayer(layer)
        snapTileLayer = layer
    }

    /// Accent border while a window drag hovers over the panel ("drop here
    /// to move it onto the virtual monitor").
    func setDropTargetHighlight(_ on: Bool) {
        guard on != (dropHighlight != nil) else { return }
        if on, let view = panel?.contentView {
            let layer = CALayer()
            layer.frame = view.bounds
            layer.borderColor = NSColor.controlAccentColor.cgColor
            layer.borderWidth = 3
            layer.cornerRadius = 10
            layer.zPosition = 3
            view.layer?.addSublayer(layer)
            dropHighlight = layer
        } else {
            dropHighlight?.removeFromSuperlayer()
            dropHighlight = nil
        }
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
        // Below the corner controls' backing layers, above the live picture.
        layer.zPosition = 1
        grabber?.layer?.zPosition = 2
        pauseButton?.layer?.zPosition = 2
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

        let grabber = DraggableImageView()
        let grabConfig = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            .applying(.init(paletteColors: [.white]))
        grabber.image = NSImage(systemSymbolName: "line.3.horizontal",
                                accessibilityDescription: "Move preview")?
            .withSymbolConfiguration(grabConfig)
        grabber.wantsLayer = true
        grabber.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        grabber.layer?.cornerRadius = Self.cornerControlSize / 2
        grabber.frame = CGRect(x: Self.cornerMargin, y: 0,
                               width: Self.cornerControlSize, height: Self.cornerControlSize)
        grabber.autoresizingMask = [.minYMargin]
        grabber.toolTip = "Move preview"
        contentView.addSubview(grabber)
        self.grabber = grabber

        let control = CornerButton()
        control.bezelStyle = .regularSquare
        control.isBordered = false
        control.target = self
        control.action = #selector(togglePassthrough)
        control.wantsLayer = true
        control.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        control.layer?.cornerRadius = Self.cornerControlSize / 2
        control.frame = CGRect(x: 0, y: 0,
                               width: Self.cornerControlSize, height: Self.cornerControlSize)
        control.autoresizingMask = [.minYMargin, .minXMargin]
        control.isHidden = true
        contentView.addSubview(control)
        controlButton = control

        let pause = CornerButton()
        pause.bezelStyle = .regularSquare
        pause.isBordered = false
        pause.target = self
        pause.action = #selector(togglePause)
        pause.wantsLayer = true
        pause.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        pause.layer?.cornerRadius = Self.cornerControlSize / 2
        pause.frame = CGRect(x: 0, y: 0,
                             width: Self.cornerControlSize, height: Self.cornerControlSize)
        pause.autoresizingMask = [.minYMargin, .minXMargin]
        contentView.addSubview(pause)
        pauseButton = pause

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
        // Always above the dim overlay (.screenSaver) — the preview must
        // never be grayed out by our own veil. Level is set last: properties
        // like isFloatingPanel silently reset it.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
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
        let top = view.bounds.height - Self.cornerControlSize - Self.cornerMargin
        grabber?.frame.origin.y = top
        pauseButton?.frame.origin = CGPoint(
            x: view.bounds.width - Self.cornerControlSize - Self.cornerMargin, y: top)
        controlButton?.frame.origin = CGPoint(
            x: view.bounds.width - 2 * Self.cornerControlSize - Self.cornerMargin - 6, y: top)
        rebuildPrivacyLayer()
    }

    @objc private func togglePause() {
        session?.togglePause()
    }

    /// Control mode: picture clicks pass through to the virtual display
    /// instead of managing its windows.
    @objc private func togglePassthrough() {
        guard let view = panel?.contentView as? PreviewContentView,
              view.pointerForwarder != nil else { return }
        view.passthroughActive.toggle()
        if view.passthroughActive {
            showSnapTile(nil)
        }
        updateControlButton()
    }

    private func updateControlButton() {
        guard let view = panel?.contentView as? PreviewContentView else { return }
        let on = view.passthroughActive
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            .applying(.init(paletteColors: [on ? .systemYellow : .white]))
        controlButton?.image = NSImage(systemSymbolName: "cursorarrow",
                                       accessibilityDescription: "Control the monitor")?
            .withSymbolConfiguration(config)
        controlButton?.toolTip = on
            ? "Control mode on — clicks pass through to the monitor"
            : "Control the monitor (clicks pass through)"
    }
}

/// Layout hook + background-drag opt-in for the preview picture. With an
/// interaction handler set (virtual-monitor mode) the picture becomes a
/// direct-manipulation surface for the monitor's windows — or, with
/// passthrough active, a remote-control surface — and the ≡ grabber is
/// then the only way to move the panel. A band along the edges is always
/// left to AppKit so borderless-window resizing keeps working.
final class PreviewContentView: NSView {
    var onLayout: (() -> Void)?
    var interactionHandler: MonitorWindowManipulator?
    var pointerForwarder: MonitorPointerForwarder?
    var passthroughActive = false

    private var monitorMode: Bool { interactionHandler != nil }
    private static let resizeBand: CGFloat = 8

    override var mouseDownCanMoveWindow: Bool { !monitorMode }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func localPoint(_ event: NSEvent) -> CGPoint {
        convert(event.locationInWindow, from: nil)
    }

    private func leaveToAppKit(_ p: CGPoint) -> Bool {
        !monitorMode || Geometry.isInResizeBand(p, bounds: bounds, band: Self.resizeBand)
    }

    override func mouseDown(with event: NSEvent) {
        let p = localPoint(event)
        guard !leaveToAppKit(p) else { return super.mouseDown(with: event) }
        if passthroughActive {
            pointerForwarder?.mouseDown(clickCount: event.clickCount, at: p,
                                        in: bounds, button: .left)
        } else {
            interactionHandler?.mouseDown(at: p, in: bounds)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard monitorMode else { return super.mouseDragged(with: event) }
        let p = localPoint(event)
        if passthroughActive {
            pointerForwarder?.mouseDragged(at: p, in: bounds, button: .left)
        } else {
            interactionHandler?.mouseDragged(to: p, in: bounds)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard monitorMode else { return super.mouseUp(with: event) }
        let p = localPoint(event)
        if passthroughActive {
            pointerForwarder?.mouseUp(clickCount: event.clickCount, at: p,
                                      in: bounds, button: .left)
        } else {
            interactionHandler?.mouseUp(at: p, in: bounds)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard monitorMode, passthroughActive else { return super.rightMouseDown(with: event) }
        pointerForwarder?.mouseDown(clickCount: event.clickCount, at: localPoint(event),
                                    in: bounds, button: .right)
    }

    override func rightMouseUp(with event: NSEvent) {
        guard monitorMode, passthroughActive else { return super.rightMouseUp(with: event) }
        pointerForwarder?.mouseUp(clickCount: event.clickCount, at: localPoint(event),
                                  in: bounds, button: .right)
    }

    override func scrollWheel(with event: NSEvent) {
        guard monitorMode, passthroughActive else { return super.scrollWheel(with: event) }
        pointerForwarder?.scroll(deltaX: event.scrollingDeltaX,
                                 deltaY: event.scrollingDeltaY,
                                 at: localPoint(event), in: bounds)
    }

    override func layout() {
        super.layout()
        onLayout?()
    }
}

/// The ≡ handle drags the panel itself — with its own event handling, so
/// the drag never falls through to the picture's window-manipulation
/// surface underneath (responder-chain fall-through moved captured windows
/// when the grabber was dragged). Anchored to NSEvent.mouseLocation, like
/// the hotbar grabber.
private final class DraggableImageView: NSImageView {
    private var anchor: (origin: CGPoint, mouse: CGPoint)?

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        anchor = (window.frame.origin, NSEvent.mouseLocation)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let anchor else { return }
        let mouse = NSEvent.mouseLocation
        window.setFrameOrigin(CGPoint(x: anchor.origin.x + mouse.x - anchor.mouse.x,
                                      y: anchor.origin.y + mouse.y - anchor.mouse.y))
    }

    override func mouseUp(with event: NSEvent) {
        anchor = nil
    }
}

/// First click must act even while another app is active (the panel never
/// activates the app).
private final class CornerButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
}
