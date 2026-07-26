import Foundation
import Combine

/// Posted whenever any setting changes; overlays observe this for live redraw.
let settingsChangedNotification = Notification.Name("RegionShareSettingsChanged")

/// UserDefaults-backed app settings. All writes persist immediately and post
/// `settingsChangedNotification`.
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private enum Key {
        static let dimOpacity = "dimOpacity"
        static let dimmingEnabled = "dimmingEnabled"
        static let showRegionBorder = "showRegionBorder"
        static let frameRate = "frameRate"
    }

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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.dimOpacity: 0.6,
            Key.dimmingEnabled: true,
            Key.showRegionBorder: true,
            Key.frameRate: 30,
        ])
        self.dimOpacity = defaults.double(forKey: Key.dimOpacity)
        self.dimmingEnabled = defaults.bool(forKey: Key.dimmingEnabled)
        self.showRegionBorder = defaults.bool(forKey: Key.showRegionBorder)
        self.frameRate = defaults.integer(forKey: Key.frameRate)
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: settingsChangedNotification, object: self)
    }
}
