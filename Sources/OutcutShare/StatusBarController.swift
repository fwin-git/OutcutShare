import AppKit

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let session: ShareSession
    private let statusItem: NSStatusItem
    private let settingsWindow: SettingsWindowController
    private let permissions: PermissionsWindowController

    private let selectItem = NSMenuItem(title: L10n.string(.menuSelectRegion),
                                        action: #selector(selectRegion), keyEquivalent: "s")
    private let shareLastItem = NSMenuItem(title: L10n.string(.menuShareLastRegion),
                                           action: #selector(shareLast), keyEquivalent: "l")
    private let presetsItem = NSMenuItem(title: L10n.string(.menuPresets),
                                         action: nil, keyEquivalent: "")
    private let zoomItem = NSMenuItem(title: L10n.string(.menuZoomInViewers),
                                      action: #selector(toggleZoom), keyEquivalent: "")
    private let moveItem = NSMenuItem(title: L10n.string(.menuMoveResizeRegion),
                                      action: #selector(moveRegion), keyEquivalent: "m")
    private let followItem = NSMenuItem(title: L10n.string(.menuFollow),
                                        action: nil, keyEquivalent: "")
    private let hotbarItem = NSMenuItem(title: L10n.string(.menuShowHotbar),
                                        action: #selector(toggleHotbar), keyEquivalent: "")
    private let pauseItem = NSMenuItem(title: L10n.string(.menuPauseSharing),
                                       action: #selector(togglePause), keyEquivalent: "p")
    private let capturesItem = NSMenuItem(title: L10n.string(.menuRecentCaptures),
                                          action: nil, keyEquivalent: "")
    private let recordItem = NSMenuItem(title: L10n.string(.menuStartRecording),
                                        action: #selector(toggleRecording), keyEquivalent: "r")
    private let stopItem = NSMenuItem(title: L10n.string(.menuStopSharing),
                                      action: #selector(stopSharing), keyEquivalent: ".")
    private let settingsItem = NSMenuItem(title: L10n.string(.menuSettings),
                                          action: #selector(openSettings), keyEquivalent: ",")
    private let permissionsItem = NSMenuItem(title: L10n.string(.menuPermissions),
                                             action: #selector(openPermissions), keyEquivalent: "")
    private let versionItem = NSMenuItem(title: L10n.string(
        .menuVersion,
        arguments: [AppVersion.display]
    ),
                                         action: nil, keyEquivalent: "")
    private let quitItem = NSMenuItem(title: L10n.string(.menuQuit),
                                      action: #selector(NSApplication.terminate(_:)),
                                      keyEquivalent: "q")

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
        // Bare square, clearly distinct from the record dot-in-circle — and
        // consistent with the hotbar's stop icon.
        stopItem.image = NSImage(systemSymbolName: "stop.fill",
                                 accessibilityDescription: nil)
        shareLastItem.target = self
        moveItem.target = self
        pauseItem.target = self
        stopItem.target = self
        presetsItem.submenu = NSMenu(title: L10n.string(.menuPresets))
        menu.addItem(selectItem)
        menu.addItem(shareLastItem)
        menu.addItem(presetsItem)
        menu.addItem(moveItem)
        menu.addItem(zoomItem)
        let followMenu = NSMenu(title: L10n.string(.menuFollow))
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
        capturesItem.submenu = NSMenu(title: L10n.string(.menuRecentCaptures))
        menu.addItem(capturesItem)
        menu.addItem(stopItem)
        menu.addItem(.separator())
        settingsItem.target = self
        menu.addItem(settingsItem)
        permissionsItem.target = self
        menu.addItem(permissionsItem)
        menu.addItem(.separator())
        versionItem.isEnabled = false
        menu.addItem(versionItem)
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
                                           accessibilityDescription: L10n.string(.appName))
        selectItem.title = SettingsStore.shared.shareMode == .virtualMonitor
            ? L10n.string(.menuStartVirtualMonitor) : L10n.string(.menuSelectRegion)
        selectItem.isEnabled = session.state == .idle
        shareLastItem.isEnabled = session.state == .idle && SettingsStore.shared.lastRegion != nil
        moveItem.isEnabled = session.isActive && !session.isVirtualMonitor
        zoomItem.isEnabled = session.isActive && !session.isVirtualMonitor
        zoomItem.title = session.isZoomedIn
            ? L10n.string(.menuZoomOutViewers) : L10n.string(.menuZoomInViewers)
        if let items = followItem.submenu?.items {
            for item in items {
                item.state = (item.representedObject as? String)
                    == SettingsStore.shared.followMode.rawValue ? .on : .off
            }
        }
        hotbarItem.state = SettingsStore.shared.hotbarEnabled ? .on : .off
        pauseItem.isEnabled = session.isActive
        pauseItem.title = session.isPaused
            ? L10n.string(.menuResumeSharing) : L10n.string(.menuPauseSharing)
        recordItem.isEnabled = session.isActive
        recordItem.title = session.isRecording
            ? L10n.string(.menuStopRecording) : L10n.string(.menuStartRecording)
        recordItem.image = NSImage(systemSymbolName: session.isRecording
                                       ? "record.circle.fill" : "record.circle",
                                   accessibilityDescription: nil)
        stopItem.isEnabled = session.isActive
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        relocalize()
        refresh()
        rebuildPresetsMenu()
        rebuildCapturesMenu()
    }

    /// Item titles resolve L10n once at creation; re-resolving them on every
    /// open keeps the menu current after a live language change. The items
    /// refresh() retitles anyway (select, zoom, pause, record) are skipped,
    /// and the presets/captures submenus are rebuilt per open.
    private func relocalize() {
        shareLastItem.title = L10n.string(.menuShareLastRegion)
        presetsItem.title = L10n.string(.menuPresets)
        presetsItem.submenu?.title = L10n.string(.menuPresets)
        moveItem.title = L10n.string(.menuMoveResizeRegion)
        followItem.title = L10n.string(.menuFollow)
        followItem.submenu?.title = L10n.string(.menuFollow)
        for item in followItem.submenu?.items ?? [] {
            guard let raw = item.representedObject as? String,
                  let mode = FollowMode(rawValue: raw) else { continue }
            item.title = mode.displayName
        }
        hotbarItem.title = L10n.string(.menuShowHotbar)
        capturesItem.title = L10n.string(.menuRecentCaptures)
        capturesItem.submenu?.title = L10n.string(.menuRecentCaptures)
        stopItem.title = L10n.string(.menuStopSharing)
        settingsItem.title = L10n.string(.menuSettings)
        permissionsItem.title = L10n.string(.menuPermissions)
        versionItem.title = L10n.string(.menuVersion, arguments: [AppVersion.display])
        quitItem.title = L10n.string(.menuQuit)
    }

    /// Last captures (pruned to files that still exist) — click brings the
    /// capture card back with copy/drag, Quick Look, trim and delete.
    private func rebuildCapturesMenu() {
        guard let submenu = capturesItem.submenu else { return }
        submenu.removeAllItems()
        let existing = SettingsStore.shared.recentCaptures.filter {
            FileManager.default.fileExists(atPath: $0)
        }
        if existing != SettingsStore.shared.recentCaptures {
            SettingsStore.shared.recentCaptures = existing
        }
        if existing.isEmpty {
            let empty = NSMenuItem(title: L10n.string(.menuNoCaptures),
                                   action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
        }
        for path in existing {
            let url = URL(fileURLWithPath: path)
            let isVideo = ["mp4", "mov"].contains(url.pathExtension.lowercased())
            let item = NSMenuItem(title: url.lastPathComponent,
                                  action: #selector(showCapture(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = path
            item.image = NSImage(systemSymbolName: isVideo ? "film" : "photo",
                                 accessibilityDescription: nil)
            submenu.addItem(item)
        }
        submenu.addItem(.separator())
        let recordings = NSMenuItem(title: L10n.string(.menuOpenRecordingsFolder),
                                    action: #selector(openRecordingsFolder),
                                    keyEquivalent: "")
        recordings.target = self
        recordings.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        submenu.addItem(recordings)
        let screenshots = NSMenuItem(title: L10n.string(.menuOpenScreenshotsFolder),
                                     action: #selector(openScreenshotsFolder),
                                     keyEquivalent: "")
        screenshots.target = self
        screenshots.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        submenu.addItem(screenshots)
    }

    @objc private func showCapture(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        session.showCaptureCard(url: URL(fileURLWithPath: path))
    }

    @objc private func openRecordingsFolder() {
        openFolder(SettingsStore.shared.recordingFolderURL)
    }

    @objc private func openScreenshotsFolder() {
        openFolder(SettingsStore.shared.screenshotFolderURL)
    }

    private func openFolder(_ url: URL) {
        try? FileManager.default.createDirectory(at: url,
                                                 withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
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
        let save = NSMenuItem(title: L10n.string(.menuSaveCurrentRegionPreset),
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

    @objc private func toggleZoom() {
        session.toggleZoom()
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
        alert.messageText = L10n.string(.presetPromptTitle)
        alert.informativeText = L10n.string(.presetPromptMessage)
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = L10n.string(
            .presetDefaultName,
            arguments: [SettingsStore.shared.presets.count + 1]
        )
        alert.accessoryView = field
        alert.addButton(withTitle: L10n.string(.presetPromptSave))
        alert.addButton(withTitle: L10n.string(.commonCancel))
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        session.saveCurrentRegionAsPreset(
            named: name.isEmpty ? L10n.string(.presetFallbackName) : name
        )
    }
}
