import AppKit
import IOSurface

/// Borderless, click-through window whose content layer shows the live
/// captured frames. Serves both share modes:
///  - virtual display: fills the virtual screen above the menu bar, so the
///    shared "monitor" shows nothing but the region, and
///  - hidden window: normal level, titled "Region Share", pinned at the
///    screen corner with 1×1 pt visible (see Geometry.hiddenWindowFrame) so
///    sharing apps list and capture it while the user never sees it.
@MainActor
final class LiveFrameWindow {
    private let window: NSWindow
    private nonisolated(unsafe) let contentLayer = CALayer()

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
