import Foundation

/// Stable technical identities used by demo choreography to find controls
/// whose visible help text changes with state or locale.
enum DemoControlID: String, CaseIterable {
    case hotbarScreenshot = "hotbar.screenshot"
    case hotbarRecording = "hotbar.recording"
    case captureImage = "capture.image"
    case captureTimeline = "capture.timeline"
    case captureTrim = "capture.trim"
    case captureSaveTrimmedCopy = "capture.saveTrimmedCopy"
}

struct HotbarRecordingPresentation {
    let controlID = DemoControlID.hotbarRecording
    let help: String

    init(
        isRecording: Bool,
        bundle: Bundle = .main,
        localeIdentifier: String? = nil
    ) {
        help = L10n.string(
            isRecording ? .menuStopRecording : .menuStartRecording,
            bundle: bundle,
            localeIdentifier: localeIdentifier
        )
    }
}
