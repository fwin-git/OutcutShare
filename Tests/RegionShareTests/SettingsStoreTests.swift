import XCTest
import AppKit
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

    func testShareModeDefaultsToVirtualDisplay() {
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.shareMode, .virtualDisplay)
    }

    func testShareModePersists() {
        let store = SettingsStore(defaults: defaults)
        store.shareMode = .hiddenWindow
        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.shareMode, .hiddenWindow)
    }

    func testDimOpacityClamped() {
        let store = SettingsStore(defaults: defaults)
        store.dimOpacity = 1.5
        XCTAssertEqual(store.dimOpacity, 0.9, accuracy: 0.0001)
        store.dimOpacity = -0.2
        XCTAssertEqual(store.dimOpacity, 0.0, accuracy: 0.0001)
    }

    func testBorderDefaults() {
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.borderStyle, .dashed)
        XCTAssertEqual(store.borderRadius, 8, accuracy: 0.0001)
        XCTAssertEqual(store.borderThickness, 3, accuracy: 0.0001)
        XCTAssertEqual(store.borderColor.hexRGBA, "#FF3B30FF")
    }

    func testBorderSettingsPersist() {
        let store = SettingsStore(defaults: defaults)
        store.borderStyle = .dotted
        store.borderRadius = 14
        store.borderThickness = 6
        store.borderColor = NSColor(hexRGBA: "#00FF00FF")!

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.borderStyle, .dotted)
        XCTAssertEqual(reloaded.borderRadius, 14, accuracy: 0.0001)
        XCTAssertEqual(reloaded.borderThickness, 6, accuracy: 0.0001)
        XCTAssertEqual(reloaded.borderColor.hexRGBA, "#00FF00FF")
    }

    func testBorderRadiusAndThicknessClamped() {
        let store = SettingsStore(defaults: defaults)
        store.borderRadius = -5
        XCTAssertEqual(store.borderRadius, 0, accuracy: 0.0001)
        store.borderRadius = 100
        XCTAssertEqual(store.borderRadius, 30, accuracy: 0.0001)
        store.borderThickness = 0
        XCTAssertEqual(store.borderThickness, 1, accuracy: 0.0001)
        store.borderThickness = 50
        XCTAssertEqual(store.borderThickness, 10, accuracy: 0.0001)
    }

    func testHexColorRoundTrip() {
        let color = NSColor(hexRGBA: "#3366CC80")
        XCTAssertNotNil(color)
        XCTAssertEqual(color?.hexRGBA, "#3366CC80")
        XCTAssertNil(NSColor(hexRGBA: "not-a-color"))
        XCTAssertNil(NSColor(hexRGBA: "#12345"))
    }

    func testChangePostsNotification() {
        let store = SettingsStore(defaults: defaults)
        let expectation = expectation(forNotification: settingsChangedNotification,
                                      object: nil)
        store.dimOpacity = 0.5
        wait(for: [expectation], timeout: 1.0)
    }
}
