import AppKit

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let session: ShareSession
    private let statusItem: NSStatusItem
    private let settingsWindow: SettingsWindowController
    private let permissions: PermissionsWindowController

    private let selectItem = NSMenuItem(title: "Select Region & Share",
                                        action: #selector(selectRegion), keyEquivalent: "s")
    private let moveItem = NSMenuItem(title: "Move / Resize Region",
                                      action: #selector(moveRegion), keyEquivalent: "m")
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
        selectItem.target = self
        moveItem.target = self
        stopItem.target = self
        menu.addItem(selectItem)
        menu.addItem(moveItem)
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
        let quitItem = NSMenuItem(title: "Quit RegionShare",
                                  action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
        statusItem.menu = menu

        session.onStateChange = { [weak self] in self?.refresh() }
        refresh()
    }

    private func refresh() {
        let symbol = session.isActive ? "rectangle.inset.filled.badge.record" : "rectangle.dashed"
        statusItem.button?.image = NSImage(systemSymbolName: symbol,
                                           accessibilityDescription: "RegionShare")
        selectItem.isEnabled = session.state == .idle
        moveItem.isEnabled = session.isActive
        stopItem.isEnabled = session.isActive
    }

    @objc private func selectRegion() {
        session.startSelection()
    }

    @objc private func moveRegion() {
        session.startAdjust()
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
