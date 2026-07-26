import AppKit
import Combine

/// Posted whenever any setting changes; overlays observe this for live redraw.
let settingsChangedNotification = Notification.Name("RegionShareSettingsChanged")

enum BorderStyle: String, CaseIterable {
    case solid, dashed, dotted
}

/// How the region is exposed to sharing apps.
enum ShareMode: String {
    /// A virtual display sized to the region ("share screen" in Zoom/Teams).
    case virtualDisplay
    /// A hidden normal-level window mirroring the region ("share window").
    case hiddenWindow
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
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: settingsChangedNotification, object: self)
    }
}
