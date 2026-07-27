import AppKit
import Carbon.HIToolbox

/// Registers the configured hotkeys system-wide via Carbon's
/// RegisterEventHotKey (needs no extra permissions) and re-registers when
/// settings change. When two actions share a combo, only the first action in
/// HotkeyAction.allCases order is registered; the settings UI surfaces the
/// conflict.
/// What a registered hotkey triggers: a fixed app action or preset N.
enum HotkeyEvent {
    case action(HotkeyAction)
    case preset(Int)
}

@MainActor
final class HotkeyManager {
    private let settings: SettingsStore
    private let perform: (HotkeyEvent) -> Void
    private var hotkeyRefs: [EventHotKeyRef] = []
    private var idToEvent: [UInt32: HotkeyEvent] = [:]
    private var eventHandler: EventHandlerRef?
    private var observer: NSObjectProtocol?
    private var appliedBindings: [HotkeyAction: KeyCombo] = [:]
    private var appliedPresetCount = -1

    private static let presetKeyCodes: [UInt32] = [18, 19, 20, 21, 23, 22, 26, 28, 25] // 1…9

    /// What actually got registered (duplicates beyond the first are skipped).
    private(set) var registered: [(label: String, combo: KeyCombo)] = []

    init(settings: SettingsStore = .shared, perform: @escaping (HotkeyEvent) -> Void) {
        self.settings = settings
        self.perform = perform
        installHandler()
        applyBindings()
        observer = NotificationCenter.default.addObserver(
            forName: settingsChangedNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyBindings() }
        }
    }

    private func applyBindings() {
        let presetCount = min(settings.presets.count, Self.presetKeyCodes.count)
        guard settings.hotkeys != appliedBindings || presetCount != appliedPresetCount else {
            return
        }
        appliedBindings = settings.hotkeys
        appliedPresetCount = presetCount
        unregisterAll()
        var used = Set<KeyCombo>()
        for (index, action) in HotkeyAction.allCases.enumerated() {
            guard let combo = settings.hotkey(for: action), used.insert(combo).inserted else {
                continue
            }
            register(combo, id: UInt32(index), event: .action(action), label: action.rawValue)
        }
        // First nine presets get fixed ⌃⌥⌘1–9 bindings.
        for index in 0..<presetCount {
            let combo = KeyCombo(keyCode: Self.presetKeyCodes[index],
                                 modifiers: [.control, .option, .command])
            guard used.insert(combo).inserted else { continue }
            register(combo, id: UInt32(100 + index), event: .preset(index), label: "preset\(index + 1)")
        }
    }

    private func register(_ combo: KeyCombo, id: UInt32, event: HotkeyEvent, label: String) {
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x5253_4852), id: id) // 'RSHR'
        let status = RegisterEventHotKey(combo.keyCode, combo.carbonModifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref {
            hotkeyRefs.append(ref)
            idToEvent[id] = event
            registered.append((label, combo))
        }
    }

    private func unregisterAll() {
        for ref in hotkeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotkeyRefs.removeAll()
        idToEvent.removeAll()
        registered.removeAll()
    }

    private func installHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr else { return status }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            Task { @MainActor in
                manager.handle(id: hotKeyID.id)
            }
            return noErr
        }, 1, &eventType, selfPtr, &eventHandler)
    }

    private func handle(id: UInt32) {
        guard let event = idToEvent[id] else { return }
        perform(event)
    }
}
