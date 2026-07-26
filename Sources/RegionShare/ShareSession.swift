import AppKit

/// Owns the lifecycle of one sharing session: selection, virtual display,
/// capture, projection and dimming. Completed in Task 8; this stub keeps the
/// status bar interface stable.
@MainActor
final class ShareSession {
    enum State { case idle, selecting, active }

    private(set) var state: State = .idle {
        didSet { onStateChange?() }
    }
    var onStateChange: (() -> Void)?
    var isActive: Bool { state == .active }

    nonisolated init() {}

    func startSelection() {
        // Wired to RegionSelector and the capture pipeline in Task 8.
    }

    func stop() {
        state = .idle
    }
}
