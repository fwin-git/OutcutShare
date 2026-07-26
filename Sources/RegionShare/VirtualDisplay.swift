import AppKit
import CVirtualDisplay

/// Owns one virtual display sized to the shared region. Releasing the
/// underlying CGVirtualDisplay (destroy/deinit) takes the display offline.
final class VirtualDisplay {
    enum VDError: LocalizedError {
        case apiUnavailable
        case creationFailed
        case screenNeverAppeared

        var errorDescription: String? {
            switch self {
            case .apiUnavailable:
                return "This macOS version does not provide the virtual display API RegionShare relies on."
            case .creationFailed:
                return "The virtual display could not be created."
            case .screenNeverAppeared:
                return "The virtual display was created but never came online."
            }
        }
    }

    let displayID: CGDirectDisplayID
    private var display: CGVirtualDisplay?

    init(sizeInPoints: CGSize, scale: CGFloat, name: String) throws {
        guard CVDApi.available(),
              let descriptor = CVDApi.makeDescriptor(),
              let settings = CVDApi.makeSettings() else {
            throw VDError.apiUnavailable
        }
        let width = UInt32(sizeInPoints.width)
        let height = UInt32(sizeInPoints.height)
        let isHiDPI = scale >= 2

        descriptor.name = name
        descriptor.queue = DispatchQueue.main
        // Physical size at ~110 ppi so the system renders text at a sane scale.
        descriptor.sizeInMillimeters = CGSize(width: Double(width) * 25.4 / 110.0,
                                              height: Double(height) * 25.4 / 110.0)
        descriptor.maxPixelsWide = isHiDPI ? width * 2 : width
        descriptor.maxPixelsHigh = isHiDPI ? height * 2 : height
        descriptor.redPrimary = CGPoint(x: 0.68, y: 0.32)
        descriptor.greenPrimary = CGPoint(x: 0.265, y: 0.69)
        descriptor.bluePrimary = CGPoint(x: 0.15, y: 0.06)
        descriptor.whitePoint = CGPoint(x: 0.3127, y: 0.329)
        descriptor.vendorID = 0x5245
        descriptor.productID = 0x4753
        descriptor.serialNum = 1

        guard let display = CVDApi.makeDisplay(with: descriptor),
              let mode = CVDApi.makeMode(withWidth: width, height: height, refresh: 60) else {
            throw VDError.creationFailed
        }
        settings.hiDPI = isHiDPI ? 1 : 0
        settings.modes = [mode]
        guard display.apply(settings) else {
            throw VDError.creationFailed
        }
        self.display = display
        self.displayID = display.displayID
    }

    /// The window server takes a moment to bring the display online; poll
    /// until its NSScreen exists (5 s cap).
    @MainActor
    func waitForScreen() async throws -> NSScreen {
        for _ in 0..<50 {
            if let screen = NSScreen.screen(for: displayID) {
                return screen
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        throw VDError.screenNeverAppeared
    }

    func destroy() {
        display = nil
    }
}
