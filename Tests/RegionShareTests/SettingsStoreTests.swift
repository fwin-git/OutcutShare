import XCTest
@testable import RegionShare

final class SettingsStoreTests: XCTestCase {
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

    func testDefaults() {
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.dimOpacity, 0.6, accuracy: 0.0001)
        XCTAssertTrue(store.dimmingEnabled)
        XCTAssertTrue(store.showRegionBorder)
        XCTAssertEqual(store.frameRate, 30)
    }

    func testPersistenceAcrossInstances() {
        let store = SettingsStore(defaults: defaults)
        store.dimOpacity = 0.35
        store.dimmingEnabled = false
        store.showRegionBorder = false
        store.frameRate = 60

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.dimOpacity, 0.35, accuracy: 0.0001)
        XCTAssertFalse(reloaded.dimmingEnabled)
        XCTAssertFalse(reloaded.showRegionBorder)
        XCTAssertEqual(reloaded.frameRate, 60)
    }

    func testDimOpacityClamped() {
        let store = SettingsStore(defaults: defaults)
        store.dimOpacity = 1.5
        XCTAssertEqual(store.dimOpacity, 0.9, accuracy: 0.0001)
        store.dimOpacity = -0.2
        XCTAssertEqual(store.dimOpacity, 0.0, accuracy: 0.0001)
    }

    func testChangePostsNotification() {
        let store = SettingsStore(defaults: defaults)
        let expectation = expectation(forNotification: settingsChangedNotification,
                                      object: nil)
        store.dimOpacity = 0.5
        wait(for: [expectation], timeout: 1.0)
    }
}
