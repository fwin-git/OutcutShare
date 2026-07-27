import XCTest
@testable import OutcutShare

final class RegionResolverTests: XCTestCase {
    private let wide = (id: UInt32(3), frame: CGRect(x: 0, y: 0, width: 2560, height: 1440))
    private let side = (id: UInt32(7), frame: CGRect(x: 2560, y: 360, width: 1920, height: 1080))

    func testExactDisplayMatchKeepsRect() {
        let rect = CGRect(x: 100, y: 100, width: 800, height: 600)
        let resolved = RegionResolver.resolve(rect: rect, displayID: 3, screens: [wide, side])
        XCTAssertEqual(resolved?.rect, rect)
        XCTAssertEqual(resolved?.screenIndex, 0)
    }

    func testMissingDisplayFallsBackToMostOverlappingScreen() {
        let rect = CGRect(x: 2700, y: 500, width: 800, height: 600)
        let resolved = RegionResolver.resolve(rect: rect, displayID: 99, screens: [wide, side])
        XCTAssertEqual(resolved?.screenIndex, 1)
        XCTAssertEqual(resolved?.rect, rect) // fits inside the side screen
    }

    func testNoOverlapFallsBackToFirstScreenClamped() {
        let rect = CGRect(x: 9000, y: 9000, width: 800, height: 600)
        let resolved = RegionResolver.resolve(rect: rect, displayID: 99, screens: [wide, side])
        XCTAssertEqual(resolved?.screenIndex, 0)
        XCTAssertEqual(resolved?.rect, CGRect(x: 1760, y: 840, width: 800, height: 600))
    }

    func testOversizedRectShrinksToFitScreen() {
        let rect = CGRect(x: 0, y: 0, width: 4000, height: 2000)
        let resolved = RegionResolver.resolve(rect: rect, displayID: 3, screens: [wide, side])
        XCTAssertEqual(resolved?.rect, CGRect(x: 0, y: 0, width: 2560, height: 1440))
    }

    func testEmptyScreensReturnsNil() {
        XCTAssertNil(RegionResolver.resolve(rect: .zero, displayID: 3, screens: []))
    }
}

final class PresetPersistenceTests: XCTestCase {
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

    func testPresetsPersistAcrossInstances() {
        let store = SettingsStore(defaults: defaults)
        XCTAssertTrue(store.presets.isEmpty)
        let preset = RegionPreset(name: "IDE",
                                  region: StoredRegion(rect: CGRect(x: 1, y: 2, width: 300, height: 200),
                                                       displayID: 3),
                                  shareModeRaw: ShareMode.hiddenWindow.rawValue)
        store.presets.append(preset)

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.presets, [preset])

        reloaded.presets.removeAll()
        XCTAssertTrue(SettingsStore(defaults: defaults).presets.isEmpty)
    }

    func testLastRegionPersists() {
        let store = SettingsStore(defaults: defaults)
        XCTAssertNil(store.lastRegion)
        let stored = StoredRegion(rect: CGRect(x: 5, y: 6, width: 700, height: 500), displayID: 3)
        store.lastRegion = stored
        XCTAssertEqual(SettingsStore(defaults: defaults).lastRegion, stored)
    }

    func testStoredRegionRoundTripsRect() {
        let stored = StoredRegion(rect: CGRect(x: 1.5, y: 2.5, width: 300, height: 200), displayID: 9)
        XCTAssertEqual(stored.rect, CGRect(x: 1.5, y: 2.5, width: 300, height: 200))
        XCTAssertEqual(stored.displayID, 9)
    }
}
