import AVFoundation
import CoreMedia

/// Writes captured region frames to an .mp4. Fed CMSampleBuffers straight
/// from the capture stream on its sample queue.
final class RecordingEngine: @unchecked Sendable {
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var systemAudioInput: AVAssetWriterInput?
    private var micInput: AVAssetWriterInput?
    private var sessionStarted = false
    private(set) var outputURL: URL?
    private(set) nonisolated(unsafe) var isRecording = false

    private static var aacSettings: [String: Any] {
        [AVFormatIDKey: kAudioFormatMPEG4AAC,
         AVSampleRateKey: 48_000,
         AVNumberOfChannelsKey: 2,
         AVEncoderBitRateKey: 160_000]
    }

    func start(pixelWidth: Int, pixelHeight: Int, to url: URL,
               systemAudio: Bool = false, microphone: Bool = false) throws {
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
        if systemAudio {
            let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: Self.aacSettings)
            audio.expectsMediaDataInRealTime = true
            if writer.canAdd(audio) {
                writer.add(audio)
                systemAudioInput = audio
            }
        }
        if microphone {
            let mic = AVAssetWriterInput(mediaType: .audio, outputSettings: Self.aacSettings)
            mic.expectsMediaDataInRealTime = true
            if writer.canAdd(mic) {
                writer.add(mic)
                micInput = mic
            }
        }
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

    /// System-audio buffers from the capture stream (its audio queue).
    /// Dropped until the writer session is anchored on the first frame.
    func appendSystemAudio(_ sample: CMSampleBuffer) {
        guard isRecording, sessionStarted,
              let systemAudioInput, systemAudioInput.isReadyForMoreMediaData else { return }
        systemAudioInput.append(sample)
    }

    /// Microphone buffers (MicCapture's queue).
    func appendMic(_ sample: CMSampleBuffer) {
        guard isRecording, sessionStarted,
              let micInput, micInput.isReadyForMoreMediaData else { return }
        micInput.append(sample)
    }

    /// Finalizes the file and returns its URL (nil if nothing was written).
    func stop() async -> URL? {
        guard let writer, let input else { return nil }
        isRecording = false
        let url = outputURL
        self.writer = nil
        self.input = nil
        let audioInputs = [systemAudioInput, micInput].compactMap { $0 }
        systemAudioInput = nil
        micInput = nil
        guard sessionStarted else {
            writer.cancelWriting()
            return nil
        }
        input.markAsFinished()
        audioInputs.forEach { $0.markAsFinished() }
        await writer.finishWriting()
        return writer.status == .completed ? url : nil
    }
}
