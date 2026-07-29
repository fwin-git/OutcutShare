import AppKit
import Carbon.HIToolbox

/// A recorded keyboard shortcut: key code plus the four standard modifiers.
struct KeyCombo: Equatable, Hashable {
    let keyCode: UInt32
    let modifiersRaw: UInt

    private static let relevantModifiers: NSEvent.ModifierFlags =
        [.command, .shift, .option, .control]

    init(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiersRaw = modifiers.intersection(Self.relevantModifiers).rawValue
    }

    var modifiers: NSEvent.ModifierFlags { .init(rawValue: modifiersRaw) }

    // MARK: Persistence

    var rawValue: String { "\(keyCode):\(modifiersRaw)" }

    init?(rawValue: String) {
        let parts = rawValue.split(separator: ":")
        guard parts.count == 2, let code = UInt32(parts[0]), let mods = UInt(parts[1]) else {
            return nil
        }
        self.init(keyCode: code, modifiers: .init(rawValue: mods))
    }

    // MARK: Display

    var displayString: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        return s + Self.keyName(for: keyCode)
    }

    // MARK: Semantics

    private static let functionKeyCodes: [UInt32: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7",
        100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13",
        107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19",
    ]

    private static let specialKeyCodes: [UInt32: String] = [
        49: "Space", 36: "↩", 76: "⌤", 53: "⎋", 51: "⌫", 117: "⌦", 48: "⇥",
        123: "←", 124: "→", 125: "↓", 126: "↑", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
    ]

    var isFunctionKey: Bool { Self.functionKeyCodes[keyCode] != nil }

    /// A bare non-function key would swallow normal typing system-wide.
    var isRisky: Bool { modifiersRaw == 0 && !isFunctionKey }

    var carbonModifiers: UInt32 {
        var flags: Int = 0
        if modifiers.contains(.command) { flags |= cmdKey }
        if modifiers.contains(.shift) { flags |= shiftKey }
        if modifiers.contains(.option) { flags |= optionKey }
        if modifiers.contains(.control) { flags |= controlKey }
        return UInt32(flags)
    }

    static func keyName(for keyCode: UInt32) -> String {
        if let name = functionKeyCodes[keyCode] ?? specialKeyCodes[keyCode] {
            return name
        }
        return layoutKeyName(for: keyCode) ?? "Key\(keyCode)"
    }

    /// Character produced by the key in the user's current keyboard layout.
    private static func layoutKeyName(for keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let dataRef = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let data = Unmanaged<CFData>.fromOpaque(dataRef).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = data.withUnsafeBytes { buffer -> OSStatus in
            guard let layout = buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else {
                return OSStatus(paramErr)
            }
            return UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
                                  UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                  &deadKeyState, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return nil }
        let name = String(utf16CodeUnits: chars, count: length)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name.uppercased()
    }
}

/// App actions that can be bound to a global hotkey.
enum HotkeyAction: String, CaseIterable {
    case selectRegion
    case adjustRegion
    case stopSharing
    case shareLastRegion
    case togglePause
    case toggleRecording
    case toggleZoom

    var displayName: String {
        switch self {
        case .selectRegion: return "Select Region & Share"
        case .adjustRegion: return "Move / Resize Region"
        case .stopSharing: return "Stop Sharing"
        case .shareLastRegion: return "Share Last Region"
        case .togglePause: return "Pause / Resume Sharing"
        case .toggleRecording: return "Start / Stop Recording"
        case .toggleZoom: return "Zoom In / Out (Viewers)"
        }
    }

    var defaultCombo: KeyCombo? {
        switch self {
        case .selectRegion: return KeyCombo(keyCode: 1, modifiers: [.control, .option, .command])  // S
        case .adjustRegion: return KeyCombo(keyCode: 46, modifiers: [.control, .option, .command]) // M
        case .stopSharing: return KeyCombo(keyCode: 7, modifiers: [.control, .option, .command])   // X
        case .shareLastRegion: return KeyCombo(keyCode: 37, modifiers: [.control, .option, .command]) // L
        case .togglePause: return KeyCombo(keyCode: 35, modifiers: [.control, .option, .command])     // P
        case .toggleRecording: return KeyCombo(keyCode: 15, modifiers: [.control, .option, .command]) // R
        case .toggleZoom: return KeyCombo(keyCode: 6, modifiers: [.control, .option, .command])       // Z
        }
    }

    /// Combos assigned to more than one action.
    static func duplicates(in bindings: [HotkeyAction: KeyCombo]) -> Set<KeyCombo> {
        var seen = Set<KeyCombo>()
        var dupes = Set<KeyCombo>()
        for combo in bindings.values where !seen.insert(combo).inserted {
            dupes.insert(combo)
        }
        return dupes
    }
}
