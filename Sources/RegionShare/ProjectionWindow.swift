import AppKit
import IOSurface

/// Borderless window filling the virtual display; captured frames land in its
/// content layer, which is what sharing apps see when that display is shared.
@MainActor
final class ProjectionWindow {
    private let window: NSWindow
    private nonisolated(unsafe) let contentLayer = CALayer()

    init(screen: NSScreen) {
        window = NSWindow(contentRect: screen.frame, styleMask: .borderless,
                          backing: .buffered, defer: false)
        window.level = .normal
        window.isOpaque = true
        window.backgroundColor = .black
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        contentLayer.frame = view.bounds
        contentLayer.contentsGravity = .resize
        contentLayer.backgroundColor = NSColor.black.cgColor
        view.layer?.addSublayer(contentLayer)
        window.contentView = view
        window.orderFrontRegardless()
    }

    /// Called from the capture sample queue; CALayer property writes are
    /// thread-safe inside an explicit transaction.
    nonisolated func display(surface: IOSurfaceRef) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentLayer.contents = surface
        CATransaction.commit()
    }

    func close() {
        window.orderOut(nil)
    }
}
