import AppKit
import Combine

/// Posted whenever any setting changes; overlays observe this for live redraw.
let settingsChangedNotification = Notification.Name("OutcutShareSettingsChanged")

/// Posted by ShareSession on any state/activity change (dock policy observes).
let sessionStateChangedNotification = Notification.Name("OutcutShareSessionStateChanged")

enum BorderStyle: String, CaseIterable {
    case solid, dashed, dotted
}

/// What viewers see while sharing is paused.
enum PauseStyle: String, CaseIterable {
    case freeze
    case privacyScreen
}

/// How follow mode moves the region.
enum FollowBehavior: String, CaseIterable {
    case snap
    case glide
}

/// Modifier that switches a preview-picture drag from window management to
/// "pull the window out onto the real screen".
enum DragOutModifier: String, CaseIterable {
    case shift, option, command, control

    var flag: NSEvent.ModifierFlags {
        switch self {
        case .shift: return .shift
        case .option: return .option
        case .command: return .command
        case .control: return .control
        }
    }

    var displayName: String {
        switch self {
        case .shift: return L10n.string(.modifierShift)
        case .option: return L10n.string(.modifierOption)
        case .command: return L10n.string(.modifierCommand)
        case .control: return L10n.string(.modifierControl)
        }
    }

    /// Bare key glyph (demo keystroke chip).
    var symbol: String {
        switch self {
        case .shift: return "⇧"
        case .option: return "⌥"
        case .command: return "⌘"
        case .control: return "⌃"
        }
    }
}

/// An app whose windows are hidden from viewers.
struct HiddenApp: Codable, Equatable, Identifiable {
    var bundleID: String
    var name: String

    var id: String { bundleID }
}

/// How the region is exposed to sharing apps.
enum ShareMode: String, CaseIterable {
    /// A virtual display sized to the region ("share screen" in Zoom/Teams).
    case virtualDisplay
    /// A hidden normal-level window mirroring the region ("share window").
    case hiddenWindow
    /// A standalone virtual screen the user places windows on — nothing from
    /// the real screen is shared; a large preview panel peeks into it.
    case virtualMonitor
}

/// UserDefaults-backed app settings. All writes persist immediately and post
/// `settingsChangedNotification`.
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private enum Key {
        static let dimOpacity = "dimOpacity"
        static let dimmingEnabled = "dimmingEnabled"
        static let showRegionBorder = "showRegionBorder"
        static let frameRate = "frameRate"
        static let shareMode = "shareMode"
        static let borderColor = "borderColor"
        static let borderRadius = "borderRadius"
        static let borderStyle = "borderStyle"
        static let borderThickness = "borderThickness"
    }

    static let defaultBorderColorHex = "#FF3B30FF"

    private let defaults: UserDefaults

    @Published var dimOpacity: Double {
        didSet {
            let clamped = min(max(dimOpacity, 0.0), 0.9)
            if clamped != dimOpacity {
                dimOpacity = clamped
                return // didSet re-runs with the clamped value
            }
            defaults.set(dimOpacity, forKey: Key.dimOpacity)
            notifyChange()
        }
    }

    @Published var dimmingEnabled: Bool {
        didSet {
            defaults.set(dimmingEnabled, forKey: Key.dimmingEnabled)
            notifyChange()
        }
    }

    @Published var showRegionBorder: Bool {
        didSet {
            defaults.set(showRegionBorder, forKey: Key.showRegionBorder)
            notifyChange()
        }
    }

    @Published var frameRate: Int {
        didSet {
            defaults.set(frameRate, forKey: Key.frameRate)
            notifyChange()
        }
    }

    @Published var shareMode: ShareMode {
        didSet {
            defaults.set(shareMode.rawValue, forKey: Key.shareMode)
            notifyChange()
        }
    }

    @Published var borderColor: NSColor {
        didSet {
            defaults.set(borderColor.hexRGBA, forKey: Key.borderColor)
            notifyChange()
        }
    }

    @Published var borderRadius: Double {
        didSet {
            let clamped = min(max(borderRadius, 0), 30)
            if clamped != borderRadius {
                borderRadius = clamped
                return
            }
            defaults.set(borderRadius, forKey: Key.borderRadius)
            notifyChange()
        }
    }

    @Published var borderStyle: BorderStyle {
        didSet {
            defaults.set(borderStyle.rawValue, forKey: Key.borderStyle)
            notifyChange()
        }
    }

    @Published var pauseStyle: PauseStyle {
        didSet {
            defaults.set(pauseStyle.rawValue, forKey: "pauseStyle")
            notifyChange()
        }
    }

    /// Empty = ~/Movies/OutcutShare.
    @Published var recordingFolder: String {
        didSet {
            defaults.set(recordingFolder, forKey: "recordingFolder")
            notifyChange()
        }
    }

    var recordingFolderURL: URL {
        if !recordingFolder.isEmpty {
            return URL(fileURLWithPath: (recordingFolder as NSString).expandingTildeInPath)
        }
        return FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OutcutShare")
    }

    /// Empty = ~/Pictures/OutcutShare.
    @Published var screenshotFolder: String {
        didSet {
            defaults.set(screenshotFolder, forKey: "screenshotFolder")
            notifyChange()
        }
    }

    var screenshotFolderURL: URL {
        if !screenshotFolder.isEmpty {
            return URL(fileURLWithPath: (screenshotFolder as NSString).expandingTildeInPath)
        }
        return FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OutcutShare")
    }

    /// Longest edge in pixels; 0 = keep the captured size.
    @Published var screenshotMaxSize: Int {
        didSet {
            defaults.set(screenshotMaxSize, forKey: "screenshotMaxSize")
            notifyChange()
        }
    }

    /// 1.0 saves lossless PNG; below that a JPEG with this quality.
    @Published var screenshotQuality: Double {
        didSet {
            defaults.set(screenshotQuality, forKey: "screenshotQuality")
            notifyChange()
        }
    }

    @Published var screenshotShadow: Bool {
        didSet {
            defaults.set(screenshotShadow, forKey: "screenshotShadow")
            notifyChange()
        }
    }

    /// Custom line on the privacy pause screen; empty = stock text.
    @Published var pauseMessage: String {
        didSet {
            defaults.set(pauseMessage, forKey: "pauseMessage")
            notifyChange()
        }
    }

    /// Custom image shown INSTEAD of icon + text while paused; empty = none.
    @Published var pauseImagePath: String {
        didSet {
            defaults.set(pauseImagePath, forKey: "pauseImagePath")
            notifyChange()
        }
    }

    /// Newest-first paths of recent captures (screenshots, recordings,
    /// trims) feeding the menu bar's Recent Captures submenu.
    @Published var recentCaptures: [String] {
        didSet {
            guard recentCaptures != oldValue else { return }
            defaults.set(recentCaptures, forKey: "recentCaptures")
            notifyChange()
        }
    }

    @Published var recordSystemAudio: Bool {
        didSet {
            defaults.set(recordSystemAudio, forKey: "recordSystemAudio")
            notifyChange()
        }
    }

    @Published var recordMicrophone: Bool {
        didSet {
            defaults.set(recordMicrophone, forKey: "recordMicrophone")
            notifyChange()
        }
    }

    @Published var cursorHighlight: Bool {
        didSet {
            defaults.set(cursorHighlight, forKey: "cursorHighlight")
            notifyChange()
        }
    }

    @Published var clickRipples: Bool {
        didSet {
            defaults.set(clickRipples, forKey: "clickRipples")
            notifyChange()
        }
    }

    /// Hides notification banners from the shared picture (Notification
    /// Center is excluded from capture; banners stay visible locally).
    @Published var hideNotificationBanners: Bool {
        didSet {
            defaults.set(hideNotificationBanners, forKey: "hideNotificationBanners")
            notifyChange()
        }
    }

    /// Apps whose windows never appear in the shared picture.
    @Published var hiddenApps: [HiddenApp] {
        didSet {
            guard hiddenApps != oldValue else { return }
            defaults.set(try? JSONEncoder().encode(hiddenApps), forKey: "hiddenApps")
            notifyChange()
        }
    }

    /// Bundle ids the capture filter must exclude right now.
    var excludedBundleIDs: [String] {
        var ids = hiddenApps.map(\.bundleID)
        if hideNotificationBanners {
            ids.append("com.apple.notificationcenterui")
        }
        return ids
    }

    /// Shows a Dock icon (and Cmd-Tab / Force Quit presence) while a session
    /// is active or the settings window is open.
    @Published var dockIconWhileActive: Bool {
        didSet {
            defaults.set(dockIconWhileActive, forKey: "dockIconWhileActive")
            notifyChange()
        }
    }

    /// Renders the virtual display with Retina (2×) backing.
    @Published var crispOutput: Bool {
        didSet {
            defaults.set(crispOutput, forKey: "crispOutput")
            notifyChange()
        }
    }

    /// Persisted follow mode; menu, settings and hotbar all drive this.
    @Published var followMode: FollowMode {
        didSet {
            defaults.set(followMode.rawValue, forKey: "followMode")
            notifyChange()
        }
    }

    /// Viewers-only zoom magnification (⌃⌥⌘Z): the capture window shrinks
    /// to region/factor while the on-screen region stays put.
    @Published var zoomFactor: Double {
        didSet {
            defaults.set(zoomFactor, forKey: "zoomFactor")
            notifyChange()
        }
    }

    /// What the hotbar's follow button starts: the last non-off follow mode
    /// used. Never .off — writers only store real targets.
    @Published var followTarget: FollowMode {
        didSet {
            guard followTarget != oldValue, followTarget != .off else { return }
            defaults.set(followTarget.rawValue, forKey: "followTarget")
            notifyChange()
        }
    }

    @Published var hotbarEnabled: Bool {
        didSet {
            defaults.set(hotbarEnabled, forKey: "hotbarEnabled")
            notifyChange()
        }
    }

    /// Floating live preview of the shared output ("what viewers see"),
    /// toggled from the hotbar. Off by default.
    @Published var previewWindowEnabled: Bool {
        didSet {
            defaults.set(previewWindowEnabled, forKey: "previewWindowEnabled")
            notifyChange()
        }
    }

    /// Resolution of the standalone virtual monitor (points).
    @Published var virtualMonitorWidth: Int {
        didSet {
            defaults.set(virtualMonitorWidth, forKey: "virtualMonitorWidth")
            notifyChange()
        }
    }

    @Published var virtualMonitorHeight: Int {
        didSet {
            defaults.set(virtualMonitorHeight, forKey: "virtualMonitorHeight")
            notifyChange()
        }
    }

    var virtualMonitorSize: CGSize {
        CGSize(width: virtualMonitorWidth, height: virtualMonitorHeight)
    }

    /// Hold this while dragging in the monitor preview to pull the window
    /// back out to the real screen.
    @Published var dragOutModifier: DragOutModifier {
        didSet {
            defaults.set(dragOutModifier.rawValue, forKey: "dragOutModifier")
            notifyChange()
        }
    }

    static var defaultShareWindowTitle: String {
        L10n.string(.settingsGeneralShareWindowDefaultTitle)
    }

    /// Title sharing apps show for the hidden share window in their window
    /// pickers. Empty/whitespace falls back to the default.
    @Published var shareWindowTitle: String {
        didSet {
            defaults.set(shareWindowTitle, forKey: "shareWindowTitle")
            notifyChange()
        }
    }

    var effectiveShareWindowTitle: String {
        let trimmed = shareWindowTitle.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? Self.defaultShareWindowTitle : trimmed
    }

    @Published var followBehavior: FollowBehavior {
        didSet {
            defaults.set(followBehavior.rawValue, forKey: "followBehavior")
            notifyChange()
        }
    }

    @Published var followResizes: Bool {
        didSet {
            defaults.set(followResizes, forKey: "followResizes")
            notifyChange()
        }
    }

    @Published var borderThickness: Double {
        didSet {
            let clamped = min(max(borderThickness, 1), 10)
            if clamped != borderThickness {
                borderThickness = clamped
                return
            }
            defaults.set(borderThickness, forKey: Key.borderThickness)
            notifyChange()
        }
    }

    /// Saved region presets, recallable from the menu (and ⌃⌥⌘1–9).
    @Published var presets: [RegionPreset] = [] {
        didSet {
            guard presets != oldValue else { return }
            defaults.set(try? JSONEncoder().encode(presets), forKey: "presets")
            notifyChange()
        }
    }

    /// The most recently shared region, for one-keystroke re-sharing.
    @Published var lastRegion: StoredRegion? {
        didSet {
            guard lastRegion != oldValue else { return }
            defaults.set(lastRegion.flatMap { try? JSONEncoder().encode($0) },
                         forKey: "lastRegion")
            notifyChange()
        }
    }

    /// Effective hotkey bindings (defaults applied, explicit clears removed).
    @Published private(set) var hotkeys: [HotkeyAction: KeyCombo] = [:]

    func hotkey(for action: HotkeyAction) -> KeyCombo? {
        hotkeys[action]
    }

    /// Pass nil to clear a binding; the clear persists across launches.
    func setHotkey(_ combo: KeyCombo?, for action: HotkeyAction) {
        hotkeys[action] = combo
        defaults.set(combo?.rawValue ?? "", forKey: Self.hotkeyKey(action))
        notifyChange()
    }

    private static func hotkeyKey(_ action: HotkeyAction) -> String {
        "hotkey.\(action.rawValue)"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.dimOpacity: 0.6,
            Key.dimmingEnabled: true,
            Key.showRegionBorder: true,
            Key.frameRate: 30,
            Key.shareMode: ShareMode.virtualDisplay.rawValue,
            Key.borderColor: Self.defaultBorderColorHex,
            Key.borderRadius: 8.0,
            Key.borderStyle: BorderStyle.dashed.rawValue,
            Key.borderThickness: 3.0,
        ])
        self.dimOpacity = defaults.double(forKey: Key.dimOpacity)
        self.dimmingEnabled = defaults.bool(forKey: Key.dimmingEnabled)
        self.showRegionBorder = defaults.bool(forKey: Key.showRegionBorder)
        self.frameRate = defaults.integer(forKey: Key.frameRate)
        self.shareMode = defaults.string(forKey: Key.shareMode)
            .flatMap(ShareMode.init(rawValue:)) ?? .virtualDisplay
        self.borderColor = defaults.string(forKey: Key.borderColor)
            .flatMap(NSColor.init(hexRGBA:))
            ?? NSColor(hexRGBA: Self.defaultBorderColorHex)!
        self.borderRadius = defaults.double(forKey: Key.borderRadius)
        self.borderStyle = defaults.string(forKey: Key.borderStyle)
            .flatMap(BorderStyle.init(rawValue:)) ?? .dashed
        self.borderThickness = defaults.double(forKey: Key.borderThickness)
        self.pauseStyle = defaults.string(forKey: "pauseStyle")
            .flatMap(PauseStyle.init(rawValue:)) ?? .privacyScreen
        defaults.register(defaults: ["followResizes": true,
                                     "cursorHighlight": true,
                                     "clickRipples": true,
                                     "hotbarEnabled": true])
        self.followMode = defaults.string(forKey: "followMode")
            .flatMap(FollowMode.init(rawValue:)) ?? .off
        self.followTarget = defaults.string(forKey: "followTarget")
            .flatMap(FollowMode.init(rawValue:))
            .flatMap { $0 == .off ? nil : $0 } ?? .activeWindow
        self.zoomFactor = defaults.object(forKey: "zoomFactor") == nil
            ? 2.0 : defaults.double(forKey: "zoomFactor")
        self.hotbarEnabled = defaults.bool(forKey: "hotbarEnabled")
        self.previewWindowEnabled = defaults.bool(forKey: "previewWindowEnabled")
        self.shareWindowTitle = defaults.string(forKey: "shareWindowTitle")
            ?? Self.defaultShareWindowTitle
        defaults.register(defaults: ["virtualMonitorWidth": 1920,
                                     "virtualMonitorHeight": 1080])
        self.virtualMonitorWidth = defaults.integer(forKey: "virtualMonitorWidth")
        self.virtualMonitorHeight = defaults.integer(forKey: "virtualMonitorHeight")
        self.dragOutModifier = defaults.string(forKey: "dragOutModifier")
            .flatMap(DragOutModifier.init(rawValue:)) ?? .shift
        self.crispOutput = defaults.bool(forKey: "crispOutput")
        self.dockIconWhileActive = defaults.bool(forKey: "dockIconWhileActive")
        defaults.register(defaults: ["hideNotificationBanners": true])
        self.hideNotificationBanners = defaults.bool(forKey: "hideNotificationBanners")
        if let data = defaults.data(forKey: "hiddenApps"),
           let decoded = try? JSONDecoder().decode([HiddenApp].self, from: data) {
            hiddenApps = decoded
        } else {
            hiddenApps = []
        }
        self.cursorHighlight = defaults.bool(forKey: "cursorHighlight")
        self.clickRipples = defaults.bool(forKey: "clickRipples")
        self.recordingFolder = defaults.string(forKey: "recordingFolder") ?? ""
        self.screenshotFolder = defaults.string(forKey: "screenshotFolder") ?? ""
        self.screenshotMaxSize = defaults.integer(forKey: "screenshotMaxSize")
        self.screenshotQuality = defaults.object(forKey: "screenshotQuality") == nil
            ? 1.0 : defaults.double(forKey: "screenshotQuality")
        self.screenshotShadow = defaults.bool(forKey: "screenshotShadow")
        self.recentCaptures = defaults.stringArray(forKey: "recentCaptures") ?? []
        self.pauseMessage = defaults.string(forKey: "pauseMessage") ?? ""
        self.pauseImagePath = defaults.string(forKey: "pauseImagePath") ?? ""
        defaults.register(defaults: ["recordSystemAudio": true])
        self.recordSystemAudio = defaults.bool(forKey: "recordSystemAudio")
        self.recordMicrophone = defaults.bool(forKey: "recordMicrophone")
        self.followBehavior = defaults.string(forKey: "followBehavior")
            .flatMap(FollowBehavior.init(rawValue:)) ?? .glide
        self.followResizes = defaults.bool(forKey: "followResizes")
        if let data = defaults.data(forKey: "presets"),
           let decoded = try? JSONDecoder().decode([RegionPreset].self, from: data) {
            presets = decoded
        }
        if let data = defaults.data(forKey: "lastRegion"),
           let decoded = try? JSONDecoder().decode(StoredRegion.self, from: data) {
            lastRegion = decoded
        }
        // Hotkeys distinguish "never set" (use default) from "cleared" (empty
        // string), so they bypass register(defaults:).
        for action in HotkeyAction.allCases {
            if let raw = defaults.string(forKey: Self.hotkeyKey(action)) {
                hotkeys[action] = raw.isEmpty ? nil : KeyCombo(rawValue: raw)
            } else {
                hotkeys[action] = action.defaultCombo
            }
        }
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: settingsChangedNotification, object: self)
    }
}
