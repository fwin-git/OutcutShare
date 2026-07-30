import AppKit
import ServiceManagement
import SwiftUI

enum SettingsTab: String, CaseIterable {
    case general, appearance, privacy, recording, presets, shortcuts, permissions, about

    var title: String {
        switch self {
        case .general: return L10n.string(.settingsTabGeneral)
        case .appearance: return L10n.string(.settingsTabAppearance)
        case .privacy: return L10n.string(.settingsTabPrivacy)
        case .recording: return L10n.string(.settingsTabRecording)
        case .presets: return L10n.string(.settingsTabPresets)
        case .shortcuts: return L10n.string(.settingsTabShortcuts)
        case .permissions: return L10n.string(.settingsTabPermissions)
        case .about: return L10n.string(.settingsTabAbout)
        }
    }

    var symbolName: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintbrush"
        case .privacy: "hand.raised"
        case .recording: "record.circle"
        case .presets: "square.grid.2x2"
        case .shortcuts: "keyboard"
        case .permissions: "checkmark.shield"
        case .about: "info.circle"
        }
    }
}

private struct PrivacyPage: View {
    @ObservedObject var settings: SettingsStore
    @State private var showAppPicker = false

    private func choosePauseImage() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        if panel.runModal() == .OK, let url = panel.url {
            settings.pauseImagePath = url.path
        }
    }

    var body: some View {
        Form {
            Section(L10n.string(.settingsPrivacyPreviewPaused)) {
                RegionPreviewCanvas(settings: settings, paused: true, showsCursor: false,
                                showsNotificationDemo: true)
            }
            Section(L10n.string(.settingsPrivacyPausing)) {
                Picker(L10n.string(.settingsPrivacyViewerSees), selection: $settings.pauseStyle) {
                    Text(L10n.string(.settingsPrivacyPauseFreeze)).tag(PauseStyle.freeze)
                    Text(L10n.string(.settingsPrivacyPausePrivacyScreen))
                        .tag(PauseStyle.privacyScreen)
                }
                .pickerStyle(.menu)
                TextField(
                    L10n.string(.settingsPrivacyPauseMessage),
                    text: $settings.pauseMessage,
                    prompt: Text(L10n.string(.settingsPrivacyPauseMessageDefault))
                )
                HStack {
                    Text(L10n.string(.settingsPrivacyPauseImage))
                    Spacer()
                    Text(settings.pauseImagePath.isEmpty
                         ? L10n.string(.settingsPrivacyNoneIconMessage)
                         : settings.pauseImagePath)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if !settings.pauseImagePath.isEmpty {
                        Button(L10n.string(.commonClear)) { settings.pauseImagePath = "" }
                    }
                    Button(L10n.string(.commonChoose)) { choosePauseImage() }
                }
                Text(L10n.string(.settingsPrivacyPauseImageCaption))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section(L10n.string(.settingsPrivacyNotifications)) {
                Toggle(
                    L10n.string(.settingsPrivacyHideNotifications),
                    isOn: $settings.hideNotificationBanners
                )
                Text(L10n.string(.settingsPrivacyNotificationsCaption))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section(L10n.string(.settingsPrivacyHiddenApps)) {
                if settings.hiddenApps.isEmpty {
                    Text(L10n.string(.settingsPrivacyNoHiddenApps))
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
                Button(L10n.string(.settingsPrivacyAddApp)) { showAppPicker = true }
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
                    Text(L10n.string(.commonPreview))
                    Spacer()
                    DemoProgressRing(progress: demoModel.progress,
                                     playing: demoModel.playing) {
                        demoModel.playing.toggle()
                    }
                    .focusEffectDisabled()
                }
            }
            Section(L10n.string(.settingsGeneralSharing)) {
                Picker(L10n.string(.settingsGeneralShareAs), selection: $settings.shareMode) {
                    Text(L10n.string(.settingsGeneralVirtualDisplay))
                        .tag(ShareMode.virtualDisplay)
                    Text(L10n.string(.settingsGeneralHiddenWindow))
                        .tag(ShareMode.hiddenWindow)
                    Text(L10n.string(.settingsGeneralVirtualMonitor))
                        .tag(ShareMode.virtualMonitor)
                }
                .pickerStyle(.menu)
                Text(shareModeCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if settings.shareMode == .virtualMonitor {
                    Picker(
                        L10n.string(.settingsGeneralMonitorResolution),
                        selection: monitorResolutionBinding
                    ) {
                        ForEach(Self.monitorResolutions, id: \.self) { res in
                            Text(verbatim: res).tag(res)
                        }
                    }
                    .pickerStyle(.menu)
                    Picker(
                        L10n.string(.settingsGeneralLayoutGridWith),
                        selection: $settings.dragOutModifier
                    ) {
                        ForEach(DragOutModifier.allCases, id: \.self) { modifier in
                            Text(modifier.displayName).tag(modifier)
                        }
                    }
                    .pickerStyle(.menu)
                    Text(L10n.string(
                        .settingsGeneralMonitorInstructions,
                        arguments: [settings.dragOutModifier.displayName]
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if settings.shareMode == .hiddenWindow {
                    TextField(
                        L10n.string(.settingsGeneralShareWindowTitle),
                        text: $settings.shareWindowTitle,
                        prompt: Text(SettingsStore.defaultShareWindowTitle)
                    )
                    Text(L10n.string(.settingsGeneralShareWindowCaption))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle(L10n.string(.settingsGeneralCrispText), isOn: $settings.crispOutput)
                    .disabled(settings.shareMode == .hiddenWindow)
                Text(L10n.string(.settingsGeneralCrispCaption))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker(
                    L10n.string(.settingsGeneralCaptureFrameRate),
                    selection: $settings.frameRate
                ) {
                    Text(L10n.string(.settingsGeneralFrameRate30)).tag(30)
                    Text(L10n.string(.settingsGeneralFrameRate60)).tag(60)
                }
                .pickerStyle(.segmented)
                Text(L10n.string(.settingsGeneralCaptureFrameRateCaption))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Picker(L10n.string(.menuFollow), selection: $settings.followMode) {
                        ForEach(FollowMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    Picker(L10n.string(.settingsGeneralMovement), selection: $settings.followBehavior) {
                        Text(L10n.string(.settingsGeneralMovementSnap)).tag(FollowBehavior.snap)
                        Text(L10n.string(.settingsGeneralMovementGlide)).tag(FollowBehavior.glide)
                    }
                    .pickerStyle(.segmented)
                    Toggle(
                        L10n.string(.settingsGeneralFollowResize),
                        isOn: $settings.followResizes
                    )
                }
            } header: {
                HStack {
                    Text(L10n.string(.settingsGeneralFollowMode))
                    Spacer()
                    Button {
                        demoModel.playing.toggle()
                    } label: {
                        Label(demoModel.playing
                              ? L10n.string(.settingsGeneralPausePreview)
                              : L10n.string(.settingsGeneralPlayPreview),
                              systemImage: demoModel.playing ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                    .font(.caption)
                    .foregroundStyle(.tint)
                }
            }
            Section(L10n.string(.settingsGeneralViewerZoom)) {
                Picker(L10n.string(.settingsGeneralMagnification), selection: $settings.zoomFactor) {
                    Text(verbatim: "1.5×").tag(1.5)
                    Text(verbatim: "2×").tag(2.0)
                    Text(verbatim: "3×").tag(3.0)
                }
                .pickerStyle(.segmented)
                Text(L10n.string(.settingsGeneralZoomCaption))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section(L10n.string(.settingsGeneralCompanions)) {
                Toggle(L10n.string(.settingsGeneralHotbarToggle), isOn: $settings.hotbarEnabled)
                Text(L10n.string(.settingsGeneralHotbarCaption))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle(
                    L10n.string(.settingsGeneralPreviewToggle),
                    isOn: $settings.previewWindowEnabled
                )
                Text(L10n.string(.settingsGeneralPreviewCaption))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section(L10n.string(.settingsGeneralSystem)) {
                Toggle(L10n.string(.settingsGeneralLaunchAtLogin), isOn: launchAtLoginBinding)
                    .disabled(!LoginItem.available)
                if !LoginItem.available {
                    Text(L10n.string(.settingsGeneralLaunchUnavailable))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle(L10n.string(.settingsGeneralDockIcon), isOn: $settings.dockIconWhileActive)
                Text(L10n.string(.settingsGeneralDockCaption))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var shareModeCaption: String {
        switch settings.shareMode {
        case .virtualDisplay:
            return L10n.string(.settingsGeneralShareModeVirtualDisplayCaption)
        case .hiddenWindow:
            return L10n.string(
                .settingsGeneralShareModeHiddenCaption,
                arguments: [settings.effectiveShareWindowTitle]
            )
        case .virtualMonitor:
            return L10n.string(.settingsGeneralShareModeVirtualMonitorCaption)
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
            Section(L10n.string(.settingsPermissionsSystem)) {
                PermissionsStatusView(model: model)
                    .padding(.vertical, 4)
            }
            if model.status.allSatisfied {
                Section {
                    Label(
                        L10n.string(.permissionsReady),
                        systemImage: "checkmark.seal.fill"
                    )
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
        .help(playing
              ? L10n.string(.settingsGeneralPausePreview)
              : L10n.string(.settingsGeneralPlayPreview))
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
            Section(L10n.string(.settingsRecordingRecording)) {
                HStack {
                    Text(L10n.string(.settingsRecordingSaveRecordings))
                    Spacer()
                    Text(verbatim: settings.recordingFolder.isEmpty
                         ? "~/Movies/OutcutShare"
                         : settings.recordingFolder)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button(L10n.string(.commonChoose)) { chooseRecordingFolder() }
                }
                Text(L10n.string(.settingsRecordingRecordingCaption))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle(
                    L10n.string(.settingsRecordingRecordSystemAudio),
                    isOn: $settings.recordSystemAudio
                )
                Toggle(
                    L10n.string(.settingsRecordingRecordMicrophone),
                    isOn: $settings.recordMicrophone
                )
                Text(L10n.string(.settingsRecordingAudioCaption))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section(L10n.string(.settingsRecordingScreenshots)) {
                HStack {
                    Text(L10n.string(.settingsRecordingSaveScreenshots))
                    Spacer()
                    Text(verbatim: settings.screenshotFolder.isEmpty
                         ? "~/Pictures/OutcutShare"
                         : settings.screenshotFolder)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button(L10n.string(.commonChoose)) { chooseScreenshotFolder() }
                }
                Picker(L10n.string(.settingsRecordingMaxSize),
                       selection: $settings.screenshotMaxSize) {
                    Text(L10n.string(.commonOriginal)).tag(0)
                    Text(verbatim: "1024 px").tag(1024)
                    Text(verbatim: "2048 px").tag(2048)
                    Text(verbatim: "4096 px").tag(4096)
                }
                .pickerStyle(.menu)
                HStack {
                    Text(L10n.string(.settingsRecordingQuality))
                    Slider(value: $settings.screenshotQuality, in: 0.5...1.0)
                    Text(settings.screenshotQuality >= 0.999
                         ? L10n.string(.settingsRecordingQualityLossless)
                         : L10n.string(
                            .settingsRecordingQualityJPEG,
                            arguments: [Int(settings.screenshotQuality * 100)]
                         ))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 96, alignment: .trailing)
                }
                Toggle(L10n.string(.settingsRecordingShadow), isOn: $settings.screenshotShadow)
                Text(L10n.string(.settingsRecordingScreenshotCaption))
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

    private func chooseScreenshotFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = settings.screenshotFolderURL
        if panel.runModal() == .OK, let url = panel.url {
            settings.screenshotFolder = url.path
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
                .accessibilityLabel(L10n.string(.settingsAboutAppIcon))
            Text(L10n.string(.alertAppTitle))
                .font(.title2.weight(.semibold))
            Text(L10n.string(.settingsAboutVersion, arguments: [AppVersion.display]))
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
            Section(L10n.string(.settingsPresetsSaved)) {
                if settings.presets.isEmpty {
                    Text(L10n.string(.settingsPresetsEmpty))
                        .foregroundStyle(.secondary)
                }
                ForEach($settings.presets) { $preset in
                    HStack {
                        TextField(L10n.string(.settingsPresetsName), text: $preset.name)
                        Spacer()
                        Text(L10n.string(
                            .settingsPresetsDimensions,
                            arguments: [
                                Int(preset.region.width),
                                Int(preset.region.height)
                            ]
                        ))
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
                Text(L10n.string(.settingsPresetsCaption))
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
            Section(L10n.string(.commonPreview)) {
                RegionPreviewCanvas(settings: settings)
            }
            Section(L10n.string(.settingsAppearanceDimming)) {
                Toggle(
                    L10n.string(.settingsAppearanceDimOutside),
                    isOn: $settings.dimmingEnabled
                )
                LabeledContent(L10n.string(.settingsAppearanceDimAmount)) {
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
                        Text(L10n.string(
                            .settingsAppearancePercent,
                            arguments: [Int((settings.dimOpacity * 100).rounded())]
                        ))
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }
            Section(L10n.string(.settingsAppearanceCursorEmphasis)) {
                Toggle(L10n.string(.settingsAppearanceHighlightCursor),
                       isOn: $settings.cursorHighlight)
                Toggle(L10n.string(.settingsAppearanceClickRipples),
                       isOn: $settings.clickRipples)
            }
            Section(L10n.string(.settingsAppearanceBorder)) {
                Toggle(L10n.string(.settingsAppearanceShowBorder),
                       isOn: $settings.showRegionBorder)
                ColorPicker(L10n.string(.settingsAppearanceColor),
                            selection: borderColorBinding,
                            supportsOpacity: true)
                    .disabled(!settings.showRegionBorder)
                Picker(L10n.string(.settingsAppearanceStyle),
                       selection: $settings.borderStyle) {
                    Text(L10n.string(.settingsAppearanceSolid)).tag(BorderStyle.solid)
                    Text(L10n.string(.settingsAppearanceDashed)).tag(BorderStyle.dashed)
                    Text(L10n.string(.settingsAppearanceDotted)).tag(BorderStyle.dotted)
                }
                .pickerStyle(.segmented)
                .disabled(!settings.showRegionBorder)
                labeledSlider(L10n.string(.settingsAppearanceThickness),
                              value: $settings.borderThickness,
                              range: 1...10)
                    .disabled(!settings.showRegionBorder)
                labeledSlider(L10n.string(.settingsAppearanceCornerRadius),
                              value: $settings.borderRadius,
                              range: 0...30)
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
            Text(L10n.string(
                .settingsAppearancePoints,
                arguments: [Int(value.wrappedValue.rounded())]
            ))
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)
        }
    }
}

/// System Settings–style window: toolbar tabs with icons, the window title
/// follows the selected pane, and the window animates to each pane's size.
@MainActor
final class SettingsWindowController {
    static let contentWidth: CGFloat = 720

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
                rootView: AnyView(GeneralPage(settings: settings)
                    .frame(width: Self.contentWidth, height: 1105)))
        case .privacy:
            controller = NSHostingController(
                rootView: AnyView(PrivacyPage(settings: settings)
                    .frame(width: Self.contentWidth, height: 800)))
        case .recording:
            controller = NSHostingController(
                rootView: AnyView(RecordingPage(settings: settings)
                    .frame(width: Self.contentWidth, height: 520)))
        case .presets:
            controller = NSHostingController(
                rootView: AnyView(PresetsPage(settings: settings)
                    .frame(width: Self.contentWidth, height: 360)))
        case .appearance:
            controller = NSHostingController(
                rootView: AnyView(AppearancePage(settings: settings)
                    .frame(width: Self.contentWidth, height: 780)))
        case .shortcuts:
            controller = NSHostingController(
                rootView: AnyView(ShortcutsPage(settings: settings)
                    .frame(width: Self.contentWidth, height: 400)))
        case .permissions:
            controller = NSHostingController(
                rootView: AnyView(PermissionsPage()
                    .frame(width: Self.contentWidth, height: 330)))
        case .about:
            controller = NSHostingController(
                rootView: AnyView(AboutPage()
                    .frame(width: Self.contentWidth, height: 260)))
        }
        controller.sizingOptions = .preferredContentSize
        // NSTabViewController propagates the selected child's title to the
        // window, giving the System Settings-style per-pane window title.
        controller.title = tab.title
        return controller
    }
}

private final class SettingsTabViewController: NSTabViewController {}
