import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            Section("Sharing") {
                Picker("Share as", selection: $settings.shareMode) {
                    Text("Virtual Display").tag(ShareMode.virtualDisplay)
                    Text("Hidden Window").tag(ShareMode.hiddenWindow)
                }
                .pickerStyle(.menu)
                Text(settings.shareMode == .virtualDisplay
                     ? "The region appears as an extra monitor — pick it under “share screen”."
                     : "The region mirrors into an invisible window named “Region Share” — pick it under “share window”.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Dimming") {
                Toggle("Dim screen outside region", isOn: $settings.dimmingEnabled)
                HStack {
                    Slider(value: $settings.dimOpacity, in: 0...0.9) {
                        Text("Dim amount")
                    }
                    .disabled(!settings.dimmingEnabled)
                    Text("\(Int((settings.dimOpacity * 100).rounded())) %")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
                Toggle("Show border around region", isOn: $settings.showRegionBorder)
            }
            Section("Capture") {
                Picker("Frame rate", selection: $settings.frameRate) {
                    Text("30 fps").tag(30)
                    Text("60 fps").tag(60)
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
        .frame(width: 380, height: 360)
    }
}

@MainActor
final class SettingsWindowController {
    private let settings: SettingsStore
    private var window: NSWindow?

    init(settings: SettingsStore) {
        self.settings = settings
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(settings: settings))
            let window = NSWindow(contentViewController: hosting)
            window.title = "RegionShare Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
