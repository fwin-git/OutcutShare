import XCTest
@testable import OutcutShare

final class VirtualMonitorSettingsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "test-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testVirtualMonitorModeRawValue() {
        XCTAssertEqual(ShareMode(rawValue: "virtualMonitor"), .virtualMonitor)
    }

    func testDefaultResolution() {
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.virtualMonitorWidth, 1920)
        XCTAssertEqual(store.virtualMonitorHeight, 1080)
    }

    func testResolutionPersistence() {
        let store = SettingsStore(defaults: defaults)
        store.virtualMonitorWidth = 2560
        store.virtualMonitorHeight = 1440

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.virtualMonitorWidth, 2560)
        XCTAssertEqual(reloaded.virtualMonitorHeight, 1440)
    }
}

final class ProminentPreviewGeometryTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 2560, height: 1440)

    func testCenteredAtRoughlyHalfScreenWidth() {
        let f = Geometry.prominentPreviewFrame(aspect: 16.0 / 9.0, screenFrame: screen)
        XCTAssertEqual(f.midX, screen.midX, accuracy: 0.5)
        XCTAssertEqual(f.midY, screen.midY, accuracy: 0.5)
        XCTAssertEqual(f.width, 2560 * 0.55, accuracy: 0.5)
        XCTAssertEqual(f.height, f.width / (16.0 / 9.0), accuracy: 0.5)
    }

    func testTallAspectClampedByHeight() {
        let f = Geometry.prominentPreviewFrame(aspect: 0.8, screenFrame: screen)
        XCTAssertEqual(f.height, 1440 * 0.75, accuracy: 0.5)
        XCTAssertEqual(f.width, f.height * 0.8, accuracy: 0.5)
        XCTAssertTrue(screen.contains(f))
    }

    func testUltrawideScreenStillFullyContains() {
        let ultrawide = CGRect(x: 0, y: 0, width: 5120, height: 1440)
        let f = Geometry.prominentPreviewFrame(aspect: 16.0 / 9.0, screenFrame: ultrawide)
        XCTAssertTrue(ultrawide.contains(f))
        XCTAssertEqual(f.midX, ultrawide.midX, accuracy: 0.5)
        // Height-limited on an ultrawide: 55% of 5120 would be too tall.
        XCTAssertEqual(f.height, 1440 * 0.75, accuracy: 0.5)
    }
}
