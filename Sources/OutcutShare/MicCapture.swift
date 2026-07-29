import AVFoundation

/// Microphone tap for recordings: default input device → CMSampleBuffers
/// on a private queue. Started per recording when the mic toggle is on.
final class MicCapture: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate,
                        @unchecked Sendable {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.outcutshare.mic")
    nonisolated(unsafe) var onSampleBuffer: ((CMSampleBuffer) -> Void)?

    func start() throws {
        guard let device = AVCaptureDevice.default(for: .audio) else {
            throw NSError(domain: "OutcutShare", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "No microphone available."])
        }
        let input = try AVCaptureDeviceInput(device: device)
        let output = AVCaptureAudioDataOutput()
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddInput(input), session.canAddOutput(output) else {
            throw NSError(domain: "OutcutShare", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Microphone could not be configured."])
        }
        session.addInput(input)
        session.addOutput(output)
        // startRunning blocks its calling thread for a moment — keep that
        // off the main thread.
        queue.async { [session] in session.startRunning() }
    }

    func stop() {
        queue.async { [session] in
            session.stopRunning()
            session.inputs.forEach(session.removeInput)
            session.outputs.forEach(session.removeOutput)
        }
        onSampleBuffer = nil
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        onSampleBuffer?(sampleBuffer)
    }
}
