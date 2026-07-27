import Foundation
import ScreenCaptureKit
import CoreMedia
import IOSurface

/// Streams the selected region of the source display via ScreenCaptureKit.
/// OutcutShare's own windows are excluded from the capture so the dim overlay
/// never leaks into the shared picture.
final class CaptureEngine: NSObject, SCStreamOutput, SCStreamDelegate {
    enum CaptureError: LocalizedError {
        case permissionDenied
        case displayNotFound

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "OutcutShare needs Screen Recording permission. "
                    + "Grant it under System Settings → Privacy & Security → Screen Recording, then try again."
            case .displayNotFound:
                return "The display containing the region is no longer available."
            }
        }
    }

    var onFrame: ((IOSurfaceRef) -> Void)?
    /// Raw sample-buffer tap (with timing) for the recording sink.
    var onSampleBuffer: ((CMSampleBuffer) -> Void)?
    var onStopped: ((Error?) -> Void)?
    /// Debug/testing aid; incremented on the sample queue, read opportunistically.
    private(set) nonisolated(unsafe) var frameCount = 0

    private var stream: SCStream?
    private var config: SCStreamConfiguration?
    private var display: SCDisplay?
    private let sampleQueue = DispatchQueue(label: "com.outcutshare.capture")

    /// - Parameter sourceRectTopLeft: region in display-local, top-left-origin
    ///   points (see `Geometry.displayLocalTopLeftRect`).
    func start(displayID: CGDirectDisplayID, sourceRectTopLeft: CGRect,
               pixelWidth: Int, pixelHeight: Int, fps: Int,
               excludedBundleIDs: [String]) async throws {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw CGPreflightScreenCaptureAccess() ? error : CaptureError.permissionDenied
        }
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.displayNotFound
        }
        self.display = display
        let filter = Self.makeFilter(content: content, display: display,
                                     excludedBundleIDs: excludedBundleIDs)

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
        // A freshly launched process may not be listed in
        // SCShareableContent.applications yet, so the own-app exclusion can
        // miss on the first filter. Re-apply once registration caught up.
        Task { [weak self] in
            for delay: UInt64 in [800_000_000, 2_000_000_000] {
                try? await Task.sleep(nanoseconds: delay)
                try? await self?.updateExclusions(excludedBundleIDs)
            }
        }
    }

    /// Application-level exclusion: our own windows plus the configured
    /// privacy exclusions. Excluding whole applications also covers windows
    /// they create later (e.g. future notification banners).
    private static func makeFilter(content: SCShareableContent, display: SCDisplay,
                                   excludedBundleIDs: [String]) -> SCContentFilter {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let excluded = content.applications.filter {
            $0.processID == ownPID || excludedBundleIDs.contains($0.bundleIdentifier)
        }
        return SCContentFilter(display: display, excludingApplications: excluded,
                               exceptingWindows: [])
    }

    /// Applies a changed privacy-exclusion list to the running stream.
    func updateExclusions(_ excludedBundleIDs: [String]) async throws {
        guard let stream, let display else { return }
        let content = try await SCShareableContent.excludingDesktopWindows(false,
                                                                           onScreenWindowsOnly: true)
        let current = content.displays.first { $0.displayID == display.displayID } ?? display
        try await stream.updateContentFilter(Self.makeFilter(content: content, display: current,
                                                             excludedBundleIDs: excludedBundleIDs))
    }

    /// Re-points (and optionally re-sizes) the running stream without
    /// interrupting the share. Pass pixel dimensions to change the output
    /// size (hidden-window resize); omit them to keep the current output and
    /// let the stream scale the new sourceRect into it (virtual-display
    /// aspect-locked resize).
    func updateCapture(sourceRectTopLeft: CGRect,
                       pixelWidth: Int? = nil, pixelHeight: Int? = nil) async throws {
        guard let stream, let config else { return }
        config.sourceRect = sourceRectTopLeft
        if let pixelWidth, let pixelHeight {
            config.width = pixelWidth
            config.height = pixelHeight
        }
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
        onSampleBuffer?(sampleBuffer)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        self.stream = nil
        onStopped?(error)
    }
}
