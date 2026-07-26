import AppKit
import SwiftUI

enum SettingsTab: String {
    case general, appearance, shortcuts
}

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @State private var selection: SettingsTab

    init(settings: SettingsStore, initialTab: SettingsTab = .general) {
        self.settings = settings
        _selection = State(initialValue: initialTab)
    }

    var body: some View {
        TabView(selection: $selection) {
            GeneralPage(settings: settings)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            AppearancePage(settings: settings)
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
                .tag(SettingsTab.appearance)
            ShortcutsPage(settings: settings)
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
                .tag(SettingsTab.shortcuts)
        }
        .frame(width: 470, height: 470)
    }
}

private struct GeneralPage: View {
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
            Section("Capture") {
                Picker("Frame rate", selection: $settings.frameRate) {
                    Text("30 fps").tag(30)
                    Text("60 fps").tag(60)
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AppearancePage: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
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
            }
            Section("Region border") {
                Toggle("Show border around region", isOn: $settings.showRegionBorder)
                ColorPicker("Color", selection: borderColorBinding, supportsOpacity: true)
                    .disabled(!settings.showRegionBorder)
                Picker("Style", selection: $settings.borderStyle) {
                    Text("Solid").tag(BorderStyle.solid)
                    Text("Dashed").tag(BorderStyle.dashed)
                    Text("Dotted").tag(BorderStyle.dotted)
                }
                .pickerStyle(.segmented)
                .disabled(!settings.showRegionBorder)
                labeledSlider("Thickness", value: $settings.borderThickness, range: 1...10)
                    .disabled(!settings.showRegionBorder)
                labeledSlider("Corner radius", value: $settings.borderRadius, range: 0...30)
                    .disabled(!settings.showRegionBorder)
            }
        }
        .formStyle(.grouped)
    }

    private var borderColorBinding: Binding<Color> {
        Binding(get: { Color(nsColor: settings.borderColor) },
                set: { settings.borderColor = NSColor($0) })
    }

    private func labeledSlider(_ label: String, value: Binding<Double>,
                               range: ClosedRange<Double>) -> some View {
        HStack {
            Slider(value: value, in: range) { Text(label) }
            Text("\(Int(value.wrappedValue.rounded())) pt")
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)
        }
    }
}

@MainActor
final class SettingsWindowController {
    private let settings: SettingsStore
    private var window: NSWindow?

    init(settings: SettingsStore) {
        self.settings = settings
    }

    func show(tab: SettingsTab? = nil) {
        if window == nil || tab != nil {
            let hosting = NSHostingController(
                rootView: SettingsView(settings: settings, initialTab: tab ?? .general))
            if let window {
                window.contentViewController = hosting
            } else {
                let window = NSWindow(contentViewController: hosting)
                window.title = "RegionShare Settings"
                window.styleMask = [.titled, .closable]
                window.isReleasedWhenClosed = false
                window.center()
                self.window = window
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
