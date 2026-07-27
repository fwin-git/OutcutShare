import AppKit
import CoreImage
import IOSurface

/// Borderless, click-through window whose content layer shows the live
/// captured frames. Serves both share modes:
///  - virtual display: fills the virtual screen above the menu bar, so the
///    shared "monitor" shows nothing but the region, and
///  - hidden window: normal level, titled "Outcut Share", pinned at the
///    screen corner with 1×1 pt visible (see Geometry.hiddenWindowFrame) so
///    sharing apps list and capture it while the user never sees it.
@MainActor
final class LiveFrameWindow {
    private let window: NSWindow
    private nonisolated(unsafe) let contentLayer = CALayer()
    private nonisolated(unsafe) var lastSurface: IOSurfaceRef?
    private var privacyLayer: CALayer?
    private var haloLayer: CALayer?

    var contentSize: CGSize { window.contentView?.bounds.size ?? .zero }

    init(contentRect: CGRect, level: NSWindow.Level, title: String? = nil) {
        window = NSWindow(contentRect: contentRect, styleMask: .borderless,
                          backing: .buffered, defer: false)
        window.level = level
        window.ignoresMouseEvents = true
        window.isOpaque = true
        window.backgroundColor = .black
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        if let title {
            window.title = title
        }

        let view = NSView(frame: NSRect(origin: .zero, size: contentRect.size))
        view.wantsLayer = true
        contentLayer.frame = view.bounds
        contentLayer.contentsGravity = .resize
        contentLayer.backgroundColor = NSColor.black.cgColor
        view.layer?.addSublayer(contentLayer)
        window.contentView = view
        window.orderFrontRegardless()
    }

    /// Live-resizes the window (hidden-window mode when the region resizes).
    func resize(to frame: CGRect) {
        window.setFrame(frame, display: true)
        if let view = window.contentView {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            contentLayer.frame = view.bounds
            CATransaction.commit()
        }
    }

    /// Called from the capture sample queue; CALayer property writes are
    /// thread-safe inside an explicit transaction.
    nonisolated func display(surface: IOSurfaceRef) {
        lastSurface = surface
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentLayer.contents = surface
        CATransaction.commit()
    }

    /// Replaces the live picture with a blurred still, a slashed-eye glyph
    /// and a note — what viewers see while sharing is paused.
    func showPrivacyScreen() {
        hidePrivacyScreen()
        guard let view = window.contentView else { return }
        let container = CALayer()
        container.frame = view.bounds
        container.backgroundColor = NSColor.black.cgColor

        if let surface = lastSurface {
            let image = CIImage(ioSurface: surface)
            let blurred = image.clampedToExtent()
                .applyingGaussianBlur(sigma: 28)
                .cropped(to: image.extent)
            if let cgImage = CIContext().createCGImage(blurred, from: image.extent) {
                let blurLayer = CALayer()
                blurLayer.frame = container.bounds
                blurLayer.contents = cgImage
                blurLayer.contentsGravity = .resizeAspectFill
                blurLayer.opacity = 0.55
                container.addSublayer(blurLayer)
            }
        }

        let iconSize: CGFloat = min(container.bounds.height * 0.25, 96)
        let config = NSImage.SymbolConfiguration(pointSize: iconSize, weight: .medium)
            .applying(.init(paletteColors: [.white]))
        if let icon = NSImage(systemSymbolName: "eye.slash.fill", accessibilityDescription: "Paused")?
            .withSymbolConfiguration(config) {
            let iconLayer = CALayer()
            var rect = CGRect(origin: .zero, size: icon.size)
            iconLayer.contents = icon.cgImage(forProposedRect: &rect, context: nil, hints: nil)
            iconLayer.frame = CGRect(x: container.bounds.midX - icon.size.width / 2,
                                     y: container.bounds.midY - icon.size.height / 2 + 14,
                                     width: icon.size.width, height: icon.size.height)
            container.addSublayer(iconLayer)
        }

        let text = CATextLayer()
        text.string = "Sharing is paused"
        text.font = NSFont.systemFont(ofSize: 22, weight: .semibold)
        text.fontSize = 22
        text.foregroundColor = NSColor.white.cgColor
        text.alignmentMode = .center
        text.contentsScale = window.backingScaleFactor
        text.frame = CGRect(x: 0, y: container.bounds.midY - iconSize / 2 - 34,
                            width: container.bounds.width, height: 30)
        container.addSublayer(text)

        view.layer?.addSublayer(container)
        privacyLayer = container
    }

    func hidePrivacyScreen() {
        privacyLayer?.removeFromSuperlayer()
        privacyLayer = nil
    }

    /// Positions (or hides, with nil) the cursor halo in content coordinates.
    func showCursorHalo(at point: CGPoint?) {
        guard let point else {
            haloLayer?.removeFromSuperlayer()
            haloLayer = nil
            return
        }
        let halo: CALayer
        if let existing = haloLayer {
            halo = existing
        } else {
            halo = CALayer()
            let diameter: CGFloat = 38
            halo.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
            halo.cornerRadius = diameter / 2
            halo.backgroundColor = NSColor.systemYellow.withAlphaComponent(0.28).cgColor
            halo.borderColor = NSColor.systemYellow.withAlphaComponent(0.85).cgColor
            halo.borderWidth = 2
            window.contentView?.layer?.addSublayer(halo)
            haloLayer = halo
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        halo.position = point
        CATransaction.commit()
    }

    /// Expanding, fading ring at the click position.
    func spawnRipple(at point: CGPoint) {
        guard let host = window.contentView?.layer else { return }
        let ripple = CAShapeLayer()
        let radius: CGFloat = 34
        ripple.path = CGPath(ellipseIn: CGRect(x: -radius, y: -radius,
                                               width: radius * 2, height: radius * 2), transform: nil)
        ripple.fillColor = nil
        ripple.strokeColor = NSColor.systemYellow.cgColor
        ripple.lineWidth = 3
        ripple.position = point
        host.addSublayer(ripple)

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.3
        scale.toValue = 1.4
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = 0.45
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        group.isRemovedOnCompletion = false
        group.fillMode = .forwards
        ripple.add(group, forKey: "ripple")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            ripple.removeFromSuperlayer()
        }
    }

    func close() {
        window.orderOut(nil)
    }
}
