import Foundation
import ScreenCaptureKit
import CoreMedia
import IOSurface

/// Streams the selected region of the source display via ScreenCaptureKit.
/// RegionShare's own windows are excluded from the capture so the dim overlay
/// never leaks into the shared picture.
final class CaptureEngine: NSObject, SCStreamOutput, SCStreamDelegate {
    enum CaptureError: LocalizedError {
        case permissionDenied
        case displayNotFound

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "RegionShare needs Screen Recording permission. "
                    + "Grant it under System Settings → Privacy & Security → Screen Recording, then try again."
            case .displayNotFound:
                return "The display containing the region is no longer available."
            }
        }
    }

    var onFrame: ((IOSurfaceRef) -> Void)?
    var onStopped: ((Error?) -> Void)?
    /// Debug/testing aid; incremented on the sample queue, read opportunistically.
    private(set) nonisolated(unsafe) var frameCount = 0

    private var stream: SCStream?
    private var config: SCStreamConfiguration?
    private let sampleQueue = DispatchQueue(label: "com.regionshare.capture")

    /// - Parameter sourceRectTopLeft: region in display-local, top-left-origin
    ///   points (see `Geometry.displayLocalTopLeftRect`).
    func start(displayID: CGDirectDisplayID, sourceRectTopLeft: CGRect,
               pixelWidth: Int, pixelHeight: Int, fps: Int) async throws {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw CGPreflightScreenCaptureAccess() ? error : CaptureError.permissionDenied
        }
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.displayNotFound
        }
        let ownWindows = content.windows.filter {
            $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier
        }
        let filter = SCContentFilter(display: display, excludingWindows: ownWindows)

        let config = SCStreamConfiguration()
        config.sourceRect = sourceRectTopLeft
        config.width = pixelWidth
        config.height = pixelHeight
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        config.showsCursor = true
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.queueDepth = 5

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        try await stream.startCapture()
        self.stream = stream
        self.config = config
    }

    /// Re-points the running stream at a new region (same size) without
    /// interrupting the share.
    func updateSourceRect(_ sourceRectTopLeft: CGRect) async throws {
        guard let stream, let config else { return }
        config.sourceRect = sourceRectTopLeft
        try await stream.updateConfiguration(config)
    }

    func stop() async {
        guard let stream else { return }
        self.stream = nil
        self.config = nil
        try? await stream.stopCapture()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer,
                    createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let statusRaw = attachments.first?[.status] as? Int,
              statusRaw == SCFrameStatus.complete.rawValue,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let surface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue()
        else { return }
        frameCount += 1
        onFrame?(surface)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        self.stream = nil
        onStopped?(error)
    }
}
