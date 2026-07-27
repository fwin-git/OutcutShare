import AppKit

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let session: ShareSession
    private let statusItem: NSStatusItem
    private let settingsWindow: SettingsWindowController
    private let permissions: PermissionsWindowController

    private let selectItem = NSMenuItem(title: "Select Region & Share",
                                        action: #selector(selectRegion), keyEquivalent: "s")
    private let shareLastItem = NSMenuItem(title: "Share Last Region",
                                           action: #selector(shareLast), keyEquivalent: "l")
    private let presetsItem = NSMenuItem(title: "Presets", action: nil, keyEquivalent: "")
    private let moveItem = NSMenuItem(title: "Move / Resize Region",
                                      action: #selector(moveRegion), keyEquivalent: "m")
    private let followItem = NSMenuItem(title: "Follow", action: nil, keyEquivalent: "")
    private let hotbarItem = NSMenuItem(title: "Show Hotbar",
                                        action: #selector(toggleHotbar), keyEquivalent: "")
    private let pauseItem = NSMenuItem(title: "Pause Sharing",
                                       action: #selector(togglePause), keyEquivalent: "p")
    private let recordItem = NSMenuItem(title: "Start Recording",
                                        action: #selector(toggleRecording), keyEquivalent: "r")
    private let stopItem = NSMenuItem(title: "Stop Sharing",
                                      action: #selector(stopSharing), keyEquivalent: ".")

    init(session: ShareSession, permissions: PermissionsWindowController) {
        self.session = session
        self.permissions = permissions
        self.settingsWindow = SettingsWindowController(settings: .shared)
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        selectItem.target = self
        selectItem.image = NSImage(systemSymbolName: "rectangle.dashed.badge.record",
                                   accessibilityDescription: nil)
        stopItem.image = NSImage(systemSymbolName: "stop.circle",
                                 accessibilityDescription: nil)
        shareLastItem.target = self
        moveItem.target = self
        pauseItem.target = self
        stopItem.target = self
        presetsItem.submenu = NSMenu(title: "Presets")
        menu.addItem(selectItem)
        menu.addItem(shareLastItem)
        menu.addItem(presetsItem)
        menu.addItem(moveItem)
        let followMenu = NSMenu(title: "Follow")
        followMenu.autoenablesItems = false
        for mode in FollowMode.allCases {
            let item = NSMenuItem(title: mode.displayName,
                                  action: #selector(setFollowMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            followMenu.addItem(item)
        }
        followItem.submenu = followMenu
        menu.addItem(followItem)
        hotbarItem.target = self
        menu.addItem(hotbarItem)
        menu.addItem(pauseItem)
        recordItem.target = self
        menu.addItem(recordItem)
        menu.addItem(stopItem)
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings…",
                                      action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        let permissionsItem = NSMenuItem(title: "Permissions…",
                                         action: #selector(openPermissions), keyEquivalent: "")
        permissionsItem.target = self
        menu.addItem(permissionsItem)
        menu.addItem(.separator())
        let versionItem = NSMenuItem(title: "OutcutShare \(AppVersion.display)",
                                     action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)
        let quitItem = NSMenuItem(title: "Quit OutcutShare",
                                  action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
        statusItem.menu = menu

        session.onStateChange = { [weak self] in self?.refresh() }
        refresh()
    }

    private func refresh() {
        let symbol: String
        if session.isActive && session.isRecording {
            symbol = "record.circle.fill"
        } else if session.isPaused && session.isActive {
            symbol = "pause.rectangle"
        } else {
            symbol = session.isActive ? "rectangle.inset.filled.badge.record" : "rectangle.dashed"
        }
        statusItem.button?.image = NSImage(systemSymbolName: symbol,
                                           accessibilityDescription: "OutcutShare")
        selectItem.isEnabled = session.state == .idle
        shareLastItem.isEnabled = session.state == .idle && SettingsStore.shared.lastRegion != nil
        moveItem.isEnabled = session.isActive
        if let items = followItem.submenu?.items {
            for item in items {
                item.state = (item.representedObject as? String)
                    == SettingsStore.shared.followMode.rawValue ? .on : .off
            }
        }
        hotbarItem.state = SettingsStore.shared.hotbarEnabled ? .on : .off
        pauseItem.isEnabled = session.isActive
        pauseItem.title = session.isPaused ? "Resume Sharing" : "Pause Sharing"
        recordItem.isEnabled = session.isActive
        recordItem.title = session.isRecording ? "Stop Recording" : "Start Recording"
        recordItem.image = NSImage(systemSymbolName: session.isRecording
                                       ? "record.circle.fill" : "record.circle",
                                   accessibilityDescription: nil)
        stopItem.isEnabled = session.isActive
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        refresh()
        rebuildPresetsMenu()
    }

    private func rebuildPresetsMenu() {
        guard let submenu = presetsItem.submenu else { return }
        submenu.removeAllItems()
        submenu.autoenablesItems = false
        let presets = SettingsStore.shared.presets
        for (index, preset) in presets.enumerated() {
            let item = NSMenuItem(title: preset.name, action: #selector(sharePreset(_:)),
                                  keyEquivalent: index < 9 ? "\(index + 1)" : "")
            item.keyEquivalentModifierMask = [.control, .option, .command]
            item.target = self
            item.representedObject = preset.id
            submenu.addItem(item)
        }
        if !presets.isEmpty {
            submenu.addItem(.separator())
        }
        let save = NSMenuItem(title: "Save Current Region as Preset…",
                              action: #selector(savePreset), keyEquivalent: "")
        save.target = self
        save.isEnabled = session.isActive
        submenu.addItem(save)
        presetsItem.isEnabled = !presets.isEmpty || session.isActive
    }

    @objc private func shareLast() {
        session.shareLastRegion()
    }

    @objc private func sharePreset(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let preset = SettingsStore.shared.presets.first(where: { $0.id == id }) else {
            return
        }
        session.sharePreset(preset)
    }

    @objc private func savePreset() {
        PresetPrompt.run(session: session)
    }

    @objc private func selectRegion() {
        session.startSelection()
    }

    @objc private func moveRegion() {
        session.startAdjust()
    }

    @objc private func setFollowMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = FollowMode(rawValue: raw) else { return }
        session.setFollow(mode: mode)
    }

    @objc private func toggleHotbar() {
        SettingsStore.shared.hotbarEnabled.toggle()
        refresh()
    }

    @objc private func togglePause() {
        session.togglePause()
    }

    @objc private func toggleRecording() {
        session.toggleRecording()
    }

    @objc private func stopSharing() {
        session.stop()
    }

    @objc private func openSettings() {
        settingsWindow.show()
    }

    @objc private func openPermissions() {
        permissions.show()
    }
}

/// Shared "name this preset" dialog used by the menu bar and the hotbar.
@MainActor
enum PresetPrompt {
    static func run(session: ShareSession) {
        let alert = NSAlert()
        alert.messageText = "Save Region as Preset"
        alert.informativeText = "Name for the current region:"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = "Preset \(SettingsStore.shared.presets.count + 1)"
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        session.saveCurrentRegionAsPreset(named: name.isEmpty ? "Preset" : name)
    }
}
