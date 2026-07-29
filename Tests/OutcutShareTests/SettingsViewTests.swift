import XCTest
@testable import OutcutShare

final class SettingsViewTests: XCTestCase {
    func testAboutIsFinalSettingsTab() {
        XCTAssertEqual(SettingsTab.allCases.count, 8)
        XCTAssertEqual(SettingsTab.allCases.last, .about)
        XCTAssertEqual(SettingsTab.allCases.last?.symbolName, "info.circle")
    }

    @MainActor
    func testSettingsWidthAccommodatesLocalizedToolbarTabs() {
        let contentWidth = SettingsWindowController.contentWidth
        XCTAssertGreaterThanOrEqual(contentWidth, 720)
    }

    /// The window content must be released on close — a retained hierarchy
    /// keeps demo timers rendering forever, which leaks observation
    /// registrations on macOS 26 until the main thread crawls.
    @MainActor
    func testSettingsWindowReleasesContentOnClose() {
        let controller = SettingsWindowController(settings: SettingsStore.shared)
        XCTAssertFalse(controller.isLoaded)
        controller.show()
        XCTAssertTrue(controller.isLoaded)
        controller.windowDidClose()
        XCTAssertFalse(controller.isLoaded)
        // Reopening rebuilds a fresh hierarchy.
        controller.show(tab: .about)
        XCTAssertTrue(controller.isLoaded)
        controller.windowDidClose()
    }
}
