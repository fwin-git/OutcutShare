import AppKit
import ServiceManagement
import SwiftUI

enum SettingsTab: String, CaseIterable {
    case general, appearance, presets, shortcuts

    var title: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .presets: return "Presets"
        case .shortcuts: return "Shortcuts"
        }
    }

    var symbolName: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "paintbrush"
        case .presets: return "square.grid.2x2"
        case .shortcuts: return "keyboard"
        }
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
                     : "The region mirrors into an invisible window named “Outcut Share” — pick it under “share window”.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Follow mode") {
                Picker("Movement", selection: $settings.followBehavior) {
                    Text("Snap").tag(FollowBehavior.snap)
                    Text("Smooth glide").tag(FollowBehavior.glide)
                }
                .pickerStyle(.segmented)
                Toggle("Resize region to the followed window", isOn: $settings.followResizes)
                Text("Enable following from the menu bar while sharing: Follow → Active Window or Cursor.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Pausing") {
                Picker("When paused, viewers see", selection: $settings.pauseStyle) {
                    Text("Frozen last frame").tag(PauseStyle.freeze)
                    Text("Privacy screen").tag(PauseStyle.privacyScreen)
                }
                .pickerStyle(.menu)
            }
            Section("Capture") {
                Picker("Frame rate", selection: $settings.frameRate) {
                    Text("30 fps").tag(30)
                    Text("60 fps").tag(60)
                }
                .pickerStyle(.segmented)
            }
            Section("Recording") {
                HStack {
                    Text("Save recordings to")
                    Spacer()
                    Text(settings.recordingFolder.isEmpty
                         ? "~/Movies/OutcutShare" : settings.recordingFolder)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Choose…") { chooseRecordingFolder() }
                }
            }
            Section("Startup") {
                Toggle("Launch at login", isOn: launchAtLoginBinding)
                    .disabled(!LoginItem.available)
                if !LoginItem.available {
                    Text("Available when running the built app bundle.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("About") {
                LabeledContent("Version", value: AppVersion.display)
            }
        }
        .formStyle(.grouped)
    }

    private func chooseRecordingFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = settings.recordingFolderURL
        if panel.runModal() == .OK, let url = panel.url {
            settings.recordingFolder = url.path
        }
    }

    @State private var launchAtLogin = LoginItem.isEnabled

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(get: { launchAtLogin },
                set: { on in
                    LoginItem.setEnabled(on)
                    launchAtLogin = LoginItem.isEnabled
                })
    }
}

@MainActor
enum LoginItem {
    static var available: Bool { Bundle.main.bundlePath.hasSuffix(".app") }

    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func setEnabled(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSSound.beep()
        }
    }
}

private struct PresetsPage: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            Section("Saved presets") {
                if settings.presets.isEmpty {
                    Text("No presets yet. While sharing, choose menu bar → Presets → "
                         + "“Save Current Region as Preset…”.")
                        .foregroundStyle(.secondary)
                }
                ForEach($settings.presets) { $preset in
                    HStack {
                        TextField("Name", text: $preset.name)
                        Spacer()
                        Text("\(Int(preset.region.width)) × \(Int(preset.region.height))")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Button {
                            settings.presets.removeAll { $0.id == preset.id }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                Text("The first nine presets are shared instantly with ⌃⌥⌘1–9.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            Section("Cursor emphasis (viewers only)") {
                Toggle("Highlight cursor", isOn: $settings.cursorHighlight)
                Toggle("Show click ripples", isOn: $settings.clickRipples)
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

/// System Settings–style window: toolbar tabs with icons, the window title
/// follows the selected pane, and the window animates to each pane's size.
@MainActor
final class SettingsWindowController {
    private let settings: SettingsStore
    private var window: NSWindow?
    private var tabController: SettingsTabViewController?

    init(settings: SettingsStore) {
        self.settings = settings
    }

    func show(tab: SettingsTab? = nil) {
        if window == nil {
            build()
        }
        if let tab, let index = SettingsTab.allCases.firstIndex(of: tab) {
            tabController?.selectedTabViewItemIndex = index
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func build() {
        let tabs = SettingsTabViewController()
        tabs.tabStyle = .toolbar
        for tab in SettingsTab.allCases {
            let item = NSTabViewItem(viewController: pageController(for: tab))
            item.label = tab.title
            item.image = NSImage(systemSymbolName: tab.symbolName,
                                 accessibilityDescription: tab.title)
            tabs.addTabViewItem(item)
        }
        tabController = tabs

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.title = SettingsTab.allCases[0].title
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
    }

    private func pageController(for tab: SettingsTab) -> NSViewController {
        let controller: NSHostingController<AnyView>
        switch tab {
        case .general:
            controller = NSHostingController(
                rootView: AnyView(GeneralPage(settings: settings).frame(width: 470, height: 680)))
        case .presets:
            controller = NSHostingController(
                rootView: AnyView(PresetsPage(settings: settings).frame(width: 470, height: 360)))
        case .appearance:
            controller = NSHostingController(
                rootView: AnyView(AppearancePage(settings: settings).frame(width: 470, height: 540)))
        case .shortcuts:
            controller = NSHostingController(
                rootView: AnyView(ShortcutsPage(settings: settings).frame(width: 470, height: 400)))
        }
        controller.sizingOptions = .preferredContentSize
        // NSTabViewController propagates the selected child's title to the
        // window, giving the System Settings-style per-pane window title.
        controller.title = tab.title
        return controller
    }
}

private final class SettingsTabViewController: NSTabViewController {}
