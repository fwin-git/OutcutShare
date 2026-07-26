import AppKit
import Carbon.HIToolbox

/// Registers the configured hotkeys system-wide via Carbon's
/// RegisterEventHotKey (needs no extra permissions) and re-registers when
/// settings change. When two actions share a combo, only the first action in
/// HotkeyAction.allCases order is registered; the settings UI surfaces the
/// conflict.
@MainActor
final class HotkeyManager {
    private let settings: SettingsStore
    private let perform: (HotkeyAction) -> Void
    private var hotkeyRefs: [EventHotKeyRef] = []
    private var idToAction: [UInt32: HotkeyAction] = [:]
    private var eventHandler: EventHandlerRef?
    private var observer: NSObjectProtocol?
    private var appliedBindings: [HotkeyAction: KeyCombo] = [:]

    /// What actually got registered (duplicates beyond the first are skipped).
    private(set) var registered: [(action: HotkeyAction, combo: KeyCombo)] = []

    init(settings: SettingsStore = .shared, perform: @escaping (HotkeyAction) -> Void) {
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
        guard settings.hotkeys != appliedBindings else { return }
        appliedBindings = settings.hotkeys
        unregisterAll()
        var used = Set<KeyCombo>()
        for (index, action) in HotkeyAction.allCases.enumerated() {
            guard let combo = settings.hotkey(for: action), used.insert(combo).inserted else {
                continue
            }
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: OSType(0x5253_4852), id: UInt32(index)) // 'RSHR'
            let status = RegisterEventHotKey(combo.keyCode, combo.carbonModifiers, hotKeyID,
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                hotkeyRefs.append(ref)
                idToAction[UInt32(index)] = action
                registered.append((action, combo))
            }
        }
    }

    private func unregisterAll() {
        for ref in hotkeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotkeyRefs.removeAll()
        idToAction.removeAll()
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
        guard let action = idToAction[id] else { return }
        perform(action)
    }
}
