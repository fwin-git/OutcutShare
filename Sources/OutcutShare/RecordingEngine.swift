import AVFoundation
import CoreMedia

/// Writes captured region frames to an .mp4. Fed CMSampleBuffers straight
/// from the capture stream on its sample queue.
final class RecordingEngine: @unchecked Sendable {
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var sessionStarted = false
    private(set) var outputURL: URL?
    private(set) nonisolated(unsafe) var isRecording = false

    func start(pixelWidth: Int, pixelHeight: Int, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: pixelWidth,
            AVVideoHeightKey: pixelHeight,
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else {
            throw NSError(domain: "OutcutShare", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot configure video writer."])
        }
        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? NSError(domain: "OutcutShare", code: 2,
                                          userInfo: [NSLocalizedDescriptionKey: "Recording could not start."])
        }
        self.writer = writer
        self.input = input
        self.outputURL = url
        sessionStarted = false
        isRecording = true
    }

    /// Called on the capture sample queue.
    func append(_ sample: CMSampleBuffer) {
        guard isRecording, let writer, let input else { return }
        if !sessionStarted {
            writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sample))
            sessionStarted = true
        }
        if input.isReadyForMoreMediaData {
            input.append(sample)
        }
    }

    /// Finalizes the file and returns its URL (nil if nothing was written).
    func stop() async -> URL? {
        guard let writer, let input else { return nil }
        isRecording = false
        let url = outputURL
        self.writer = nil
        self.input = nil
        guard sessionStarted else {
            writer.cancelWriting()
            return nil
        }
        input.markAsFinished()
        await writer.finishWriting()
        return writer.status == .completed ? url : nil
    }
}
