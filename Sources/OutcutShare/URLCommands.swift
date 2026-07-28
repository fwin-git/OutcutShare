import Foundation

/// Presenter options togglable via outcutshare://toggle?option=…
enum URLToggleOption: String, CaseIterable {
    case preview
    case hotbar
    case cursorHighlights
    case dimming
}

/// Commands accepted over the outcutshare:// URL scheme (Raycast, shell,
/// any automation tool). Grammar documented in docs/raycast.md.
enum URLCommand: Equatable {
    case select
    case shareLast
    case preset(id: String?, name: String?)
    case stop
    case togglePause
    case toggleRecording
    case follow(FollowMode)
    case shareMode(ShareMode)
    case toggle(URLToggleOption)

    static func parse(_ url: URL) -> URLCommand? {
        guard url.scheme?.lowercased() == "outcutshare" else { return nil }
        let command = url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var params: [String: String] = [:]
        for item in URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [] {
            params[item.name.lowercased()] = item.value
        }
        switch command.lowercased() {
        case "select": return .select
        case "share-last": return .shareLast
        case "preset":
            let id = params["id"], name = params["name"]
            guard id != nil || name != nil else { return nil }
            return .preset(id: id, name: name)
        case "stop": return .stop
        case "pause": return .togglePause
        case "record": return .toggleRecording
        case "follow":
            guard let mode = params["mode"].flatMap(FollowMode.init(caseInsensitive:))
            else { return nil }
            return .follow(mode)
        case "share-mode":
            guard let mode = params["mode"].flatMap(ShareMode.init(caseInsensitive:))
            else { return nil }
            return .shareMode(mode)
        case "toggle":
            guard let option = params["option"].flatMap(URLToggleOption.init(caseInsensitive:))
            else { return nil }
            return .toggle(option)
        default:
            return nil
        }
    }

    /// id (exact UUID string, any case) wins; then exact name, then the
    /// first case-insensitive name match.
    static func matchPreset(id: String?, name: String?,
                            in presets: [RegionPreset]) -> RegionPreset? {
        if let id, let match = presets.first(where: {
            $0.id.uuidString.caseInsensitiveCompare(id) == .orderedSame }) {
            return match
        }
        guard let name else { return nil }
        return presets.first { $0.name == name }
            ?? presets.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }
}

extension RawRepresentable where Self: CaseIterable, RawValue == String {
    fileprivate init?(caseInsensitive raw: String) {
        guard let match = Self.allCases.first(where: {
            $0.rawValue.caseInsensitiveCompare(raw) == .orderedSame }) else { return nil }
        self = match
    }
}
