import XCTest
@testable import OutcutShare

final class SettingsViewTests: XCTestCase {
    func testAboutIsFinalSettingsTab() {
        XCTAssertEqual(SettingsTab.allCases.count, 6)
        XCTAssertEqual(SettingsTab.allCases.last?.title, "About")
        XCTAssertEqual(SettingsTab.allCases.last?.symbolName, "info.circle")
    }
}
