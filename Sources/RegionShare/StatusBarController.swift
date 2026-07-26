import AppKit

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let session: ShareSession
    private let statusItem: NSStatusItem
    private let settingsWindow: SettingsWindowController

    private let selectItem = NSMenuItem(title: "Select Region & Share",
                                        action: #selector(selectRegion), keyEquivalent: "s")
    private let moveItem = NSMenuItem(title: "Move Region",
                                      action: #selector(moveRegion), keyEquivalent: "m")
    private let stopItem = NSMenuItem(title: "Stop Sharing",
                                      action: #selector(stopSharing), keyEquivalent: ".")

    init(session: ShareSession) {
        self.session = session
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
        session.startMove()
    }

    @objc private func stopSharing() {
        session.stop()
    }

    @objc private func openSettings() {
        settingsWindow.show()
    }
}
