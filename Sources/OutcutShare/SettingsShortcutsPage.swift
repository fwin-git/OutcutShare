import AppKit
import SwiftUI

/// Captures the next key press in-app while recording a shortcut.
@MainActor
final class KeyRecorder: ObservableObject {
    @Published private(set) var recordingAction: HotkeyAction?
    private var monitor: Any?

    func begin(for action: HotkeyAction, onCapture: @escaping (KeyCombo) -> Void) {
        cancel()
        recordingAction = action
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = UInt32(event.keyCode)
            let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
            var swallow = false
            MainActor.assumeIsolated { // local monitors fire on the main thread
                guard let self, self.recordingAction != nil else { return }
                self.cancel()
                swallow = true
                if keyCode == 53 && modifiers.isEmpty {
                    return // Esc aborts recording without changes
                }
                onCapture(KeyCombo(keyCode: keyCode, modifiers: modifiers))
            }
            return swallow ? nil : event
        }
    }

    func cancel() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        recordingAction = nil
    }
}

struct ShortcutsPage: View {
    @ObservedObject var settings: SettingsStore
    @StateObject private var recorder = KeyRecorder()

    var body: some View {
        Form {
            Section("Global shortcuts") {
                ForEach(HotkeyAction.allCases, id: \.self) { action in
                    row(for: action)
                }
            }
            Section {
                Text("Shortcuts work system-wide while OutcutShare is running. "
                     + "Any key combination can be recorded — Esc cancels recording.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onDisappear { recorder.cancel() }
    }

    private func row(for action: HotkeyAction) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(action.displayName)
                Spacer()
                if recorder.recordingAction == action {
                    Text("Press keys…")
                        .foregroundStyle(.orange)
                } else if let combo = settings.hotkey(for: action) {
                    Text(combo.displayString)
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                } else {
                    Text("none").foregroundStyle(.secondary)
                }
                Button(recorder.recordingAction == action ? "Cancel" : "Record") {
                    if recorder.recordingAction == action {
                        recorder.cancel()
                    } else {
                        recorder.begin(for: action) { combo in
                            settings.setHotkey(combo, for: action)
                        }
                    }
                }
                Button {
                    settings.setHotkey(nil, for: action)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(settings.hotkey(for: action) == nil)
                .help("Remove shortcut")
            }
            warnings(for: action)
        }
    }

    @ViewBuilder
    private func warnings(for action: HotkeyAction) -> some View {
        if let combo = settings.hotkey(for: action) {
            if HotkeyAction.duplicates(in: settings.hotkeys).contains(combo) {
                Label("Also assigned to \(conflictNames(for: action, combo: combo)) — "
                      + "only the first assignment is active.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if combo.isRisky {
                Label("No modifier key — this swallows every “\(KeyCombo.keyName(for: combo.keyCode))” "
                      + "keystroke system-wide.",
                      systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func conflictNames(for action: HotkeyAction, combo: KeyCombo) -> String {
        HotkeyAction.allCases
            .filter { $0 != action && settings.hotkey(for: $0) == combo }
            .map { "“\($0.displayName)”" }
            .joined(separator: ", ")
    }
}
