import AppKit
import ServiceManagement
import SwiftUI

enum SettingsTab: String, CaseIterable {
    case general, appearance, privacy, recording, presets, shortcuts, permissions, about

    var title: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .privacy: return "Privacy"
        case .recording: return "Recording"
        case .presets: return "Presets"
        case .shortcuts: return "Shortcuts"
        case .permissions: return "Permissions"
        case .about: return "About"
        }
    }

    var symbolName: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "paintbrush"
        case .privacy: return "hand.raised"
        case .recording: return "record.circle"
        case .presets: return "square.grid.2x2"
        case .shortcuts: return "keyboard"
        case .permissions: return "checkmark.shield"
        case .about: return "info.circle"
        }
    }
}

private struct PrivacyPage: View {
    @ObservedObject var settings: SettingsStore
    @State private var showAppPicker = false

    var body: some View {
        Form {
            Section("Preview — while paused") {
                RegionPreviewCanvas(settings: settings, paused: true, showsCursor: false,
                                showsNotificationDemo: true)
            }
            Section("Pausing") {
                Picker("When paused, viewers see", selection: $settings.pauseStyle) {
                    Text("Frozen last frame").tag(PauseStyle.freeze)
                    Text("Privacy screen").tag(PauseStyle.privacyScreen)
                }
                .pickerStyle(.menu)
            }
            Section("Notifications") {
                Toggle("Hide notification banners from viewers", isOn: $settings.hideNotificationBanners)
                Text("Banners still appear on your screen — they're removed only from the shared picture.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Hidden apps") {
                if settings.hiddenApps.isEmpty {
                    Text("No hidden apps. Windows of apps you add here never appear "
                         + "in the shared picture — viewers see what's behind them.")
                        .foregroundStyle(.secondary)
                }
                ForEach(settings.hiddenApps) { app in
                    HStack {
                        Image(nsImage: Self.icon(forBundleID: app.bundleID))
                            .resizable()
                            .frame(width: 20, height: 20)
                        Text(app.name)
                        Spacer()
                        Text(app.bundleID)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button {
                            settings.hiddenApps.removeAll { $0.bundleID == app.bundleID }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
                Button("Add App…") { showAppPicker = true }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showAppPicker) {
            AppPickerSheet(settings: settings)
        }
    }

    static func icon(forBundleID bundleID: String) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)
            ?? NSImage()
    }
}

private struct GeneralPage: View {
    @ObservedObject var settings: SettingsStore
    @StateObject private var demoModel = FollowDemoModel()

    var body: some View {
        Form {
            Section {
                RegionPreviewCanvas(settings: settings, showsHotbar: true,
                                    demoActive: demoModel.playing, demoModel: demoModel)
            } header: {
                HStack {
                    Text("Preview")
                    Spacer()
                    DemoProgressRing(progress: demoModel.progress,
                                     playing: demoModel.playing) {
                        demoModel.playing.toggle()
                    }
                    .focusEffectDisabled()
                }
            }
            Section("Sharing") {
                Picker("Share as", selection: $settings.shareMode) {
                    Text("Virtual Display").tag(ShareMode.virtualDisplay)
                    Text("Hidden Window").tag(ShareMode.hiddenWindow)
                    Text("Virtual Monitor").tag(ShareMode.virtualMonitor)
                }
                .pickerStyle(.menu)
                Text(shareModeCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if settings.shareMode == .virtualMonitor {
                    Picker("Monitor resolution", selection: monitorResolutionBinding) {
                        ForEach(Self.monitorResolutions, id: \.self) { res in
                            Text(res).tag(res)
                        }
                    }
                    .pickerStyle(.menu)
                    Picker("Layout grid with", selection: $settings.dragOutModifier) {
                        ForEach(DragOutModifier.allCases, id: \.self) { modifier in
                            Text(modifier.displayName).tag(modifier)
                        }
                    }
                    .pickerStyle(.menu)
                    Text("In the preview: drag a window to move it — drop anywhere on the "
                         + "monitor, or off the panel to bring it back to your real screen. "
                         + "Hold \(settings.dragOutModifier.displayName) for the 3 × 3 layout "
                         + "grid: drop in a cell, or sweep across cells to span a block. The "
                         + "cursor button switches to control mode — clicks pass through to "
                         + "the monitor.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if settings.shareMode == .hiddenWindow {
                    TextField("Share window title", text: $settings.shareWindowTitle,
                              prompt: Text(SettingsStore.defaultShareWindowTitle))
                    Text("The name sharing apps list for the share window in their window pickers.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("Crisp text (Retina output)", isOn: $settings.crispOutput)
                    .disabled(settings.shareMode == .hiddenWindow)
                Text("Renders the shared monitor at 2× pixel density: sharpest with Retina "
                     + "sources, reduces compression artifacts otherwise. Uses more bandwidth. "
                     + "Virtual Display mode only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Capture frame rate", selection: $settings.frameRate) {
                    Text("30 fps").tag(30)
                    Text("60 fps").tag(60)
                }
                .pickerStyle(.segmented)
                Text("Applies to both the shared picture and recordings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Follow", selection: $settings.followMode) {
                        ForEach(FollowMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    Picker("Movement", selection: $settings.followBehavior) {
                        Text("Snap").tag(FollowBehavior.snap)
                        Text("Smooth glide").tag(FollowBehavior.glide)
                    }
                    .pickerStyle(.segmented)
                    Toggle("Resize region to the followed window", isOn: $settings.followResizes)
                }
            } header: {
                HStack {
                    Text("Follow mode")
                    Spacer()
                    Button {
                        demoModel.playing.toggle()
                    } label: {
                        Label(demoModel.playing ? "Pause preview animation"
                                                : "Play preview animation",
                              systemImage: demoModel.playing ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                    .font(.caption)
                    .foregroundStyle(.tint)
                }
            }
            Section("Companions") {
                Toggle("Show floating hotbar while sharing", isOn: $settings.hotbarEnabled)
                Text("Quick actions next to the region. Drag the ≡ grabber to reposition; ✕ hides it until re-enabled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Show shared-output preview while sharing", isOn: $settings.previewWindowEnabled)
                Text("A small floating window with exactly what viewers see — no need to keep "
                     + "Zoom or Teams open. Docks next to the region, drags anywhere, resizes "
                     + "within its aspect ratio; its corner button pauses sharing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("System") {
                Toggle("Launch at login", isOn: launchAtLoginBinding)
                    .disabled(!LoginItem.available)
                if !LoginItem.available {
                    Text("Available when running the built app bundle.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("Show Dock icon while active", isOn: $settings.dockIconWhileActive)
                Text("Adds the app to the Dock, ⌘-Tab switcher and Force Quit while "
                     + "you're sharing or this settings window is open. Otherwise "
                     + "Outcut Share stays a menu-bar-only app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var shareModeCaption: String {
        switch settings.shareMode {
        case .virtualDisplay:
            return "The region appears as an extra monitor — pick it under “share screen”."
        case .hiddenWindow:
            return "The region mirrors into an invisible window named “\(settings.effectiveShareWindowTitle)” — pick it under “share window”."
        case .virtualMonitor:
            return "A separate empty screen — drag windows onto it and only they are shared. "
                + "A large preview panel shows what's on it; share it under “share screen”."
        }
    }

    static let monitorResolutions = ["1280 × 720", "1600 × 900", "1920 × 1080",
                                     "2560 × 1440", "3440 × 1440"]

    private var monitorResolutionBinding: Binding<String> {
        Binding(get: {
            "\(settings.virtualMonitorWidth) × \(settings.virtualMonitorHeight)"
        }, set: { label in
            let parts = label.split(separator: "×").compactMap {
                Int($0.trimmingCharacters(in: .whitespaces))
            }
            guard parts.count == 2 else { return }
            settings.virtualMonitorWidth = parts[0]
            settings.virtualMonitorHeight = parts[1]
        })
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

private struct PermissionsPage: View {
    @StateObject private var model = PermissionsModel()

    var body: some View {
        Form {
            Section("System permissions") {
                PermissionsStatusView(model: model)
                    .padding(.vertical, 4)
            }
            if model.status.allSatisfied {
                Section {
                    Label("All set — you're ready to share.", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { model.startPolling() }
        .onDisappear { model.stopPolling() }
    }
}

private struct DemoProgressRing: View {
    // The only view observing the 20 Hz progress — keeps high-frequency
    // re-renders confined to this 14 pt circle (see FollowDemoModel).
    @ObservedObject var progress: DemoProgress
    var playing: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ring
        }
        .buttonStyle(.plain)
        .help(playing ? "Pause preview animation" : "Play preview animation")
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.25), lineWidth: 2)
            Circle()
                .trim(from: 0, to: progress.value)
                .stroke(Color.accentColor,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: playing ? "pause.fill" : "play.fill")
                .font(.system(size: 5.5, weight: .bold))
                .foregroundStyle(.secondary)
        }
        .frame(width: 14, height: 14)
    }
}

private struct RecordingPage: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
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
                Text("Start/stop with ⌃⌥⌘R, the hotbar, or the menu bar while sharing. "
                     + "Recordings use the capture frame rate set under General and pause "
                     + "together with privacy pause.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
}

private struct AboutPage: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 96, height: 96)
                .accessibilityLabel("Outcut Share app icon")
            Text("Outcut Share")
                .font(.title2.weight(.semibold))
            Text("Version \(AppVersion.display)")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
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
            Section("Preview") {
                RegionPreviewCanvas(settings: settings)
            }
            Section("Dimming") {
                Toggle("Dim screen outside region", isOn: $settings.dimmingEnabled)
                LabeledContent("Dim amount") {
                    HStack {
                        Slider(value: $settings.dimOpacity, in: 0...0.9,
                               onEditingChanged: { editing in
                                   // Live full-screen dim behind the settings
                                   // window while dragging.
                                   if editing {
                                       DimPreview.shared.begin()
                                   } else {
                                       DimPreview.shared.end()
                                   }
                               })
                            .disabled(!settings.dimmingEnabled)
                        Text("\(Int((settings.dimOpacity * 100).rounded())) %")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
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
    private var closeObserver: NSObjectProtocol?

    init(settings: SettingsStore) {
        self.settings = settings
    }

    var isLoaded: Bool { window != nil }

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

    /// Releases the whole tab hierarchy when the window closes. Keeping it
    /// alive kept every page's SwiftUI graph (and its demo timers) running
    /// forever, which on macOS 26 leaks observation-tracking registrations
    /// per render until the main thread crawls. Rebuilding on next open is
    /// cheap; state lives in SettingsStore anyway.
    ///
    /// Dropping our references is NOT enough: NSTabViewController's toolbar
    /// items strongly target the controller while it retains the toolbar, a
    /// cycle that outlives the window and keeps every page (and its timers)
    /// alive. The tab items must be removed explicitly.
    func windowDidClose() {
        if let closeObserver {
            NotificationCenter.default.removeObserver(closeObserver)
            self.closeObserver = nil
        }
        if let tabController {
            while let item = tabController.tabViewItems.first {
                tabController.removeTabViewItem(item)
            }
        }
        window?.toolbar = nil
        window?.contentViewController = nil
        window = nil
        tabController = nil
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
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            // Deferred: tearing the toolbar/tab items out mid-close would
            // re-enter AppKit's close handling.
            DispatchQueue.main.async {
                guard let self, self.window?.isVisible != true else { return }
                self.windowDidClose()
            }
        }
    }

    private func pageController(for tab: SettingsTab) -> NSViewController {
        let controller: NSHostingController<AnyView>
        switch tab {
        case .general:
            controller = NSHostingController(
                rootView: AnyView(GeneralPage(settings: settings).frame(width: 560, height: 1105)))
        case .privacy:
            controller = NSHostingController(
                rootView: AnyView(PrivacyPage(settings: settings).frame(width: 560, height: 800)))
        case .recording:
            controller = NSHostingController(
                rootView: AnyView(RecordingPage(settings: settings).frame(width: 560, height: 230)))
        case .presets:
            controller = NSHostingController(
                rootView: AnyView(PresetsPage(settings: settings).frame(width: 560, height: 360)))
        case .appearance:
            controller = NSHostingController(
                rootView: AnyView(AppearancePage(settings: settings).frame(width: 560, height: 780)))
        case .shortcuts:
            controller = NSHostingController(
                rootView: AnyView(ShortcutsPage(settings: settings).frame(width: 560, height: 400)))
        case .permissions:
            controller = NSHostingController(
                rootView: AnyView(PermissionsPage().frame(width: 560, height: 330)))
        case .about:
            controller = NSHostingController(
                rootView: AnyView(AboutPage().frame(width: 560, height: 260)))
        }
        controller.sizingOptions = .preferredContentSize
        // NSTabViewController propagates the selected child's title to the
        // window, giving the System Settings-style per-pane window title.
        controller.title = tab.title
        return controller
    }
}

private final class SettingsTabViewController: NSTabViewController {}
