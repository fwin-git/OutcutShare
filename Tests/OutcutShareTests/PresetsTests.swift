import XCTest
@testable import OutcutShare

final class PresetSwitchTests: XCTestCase {
    private let wide = (id: UInt32(3), frame: CGRect(x: 0, y: 0, width: 2560, height: 1440))
    private let side = (id: UInt32(7), frame: CGRect(x: 2560, y: 360, width: 1920, height: 1080))
    private var screens: [(id: UInt32, frame: CGRect)] { [wide, side] }
    private let current = CGRect(x: 100, y: 100, width: 800, height: 600)

    func testSameDisplaySameModeSwitchesLive() {
        let target = PresetSwitch.liveTarget(
            presetRect: CGRect(x: 900, y: 200, width: 600, height: 400),
            presetDisplayID: 3, presetMode: .hiddenWindow, activeMode: .hiddenWindow,
            currentRect: current, currentScreenID: 3, screens: screens)
        XCTAssertEqual(target, CGRect(x: 900, y: 200, width: 600, height: 400))
    }

    func testDifferentModeOrMonitorRestarts() {
        XCTAssertNil(PresetSwitch.liveTarget(
            presetRect: current, presetDisplayID: 3,
            presetMode: .virtualDisplay, activeMode: .hiddenWindow,
            currentRect: current, currentScreenID: 3, screens: screens))
        XCTAssertNil(PresetSwitch.liveTarget(
            presetRect: current, presetDisplayID: 3,
            presetMode: .virtualMonitor, activeMode: .virtualMonitor,
            currentRect: current, currentScreenID: 3, screens: screens))
    }

    func testOtherDisplayRestarts() {
        XCTAssertNil(PresetSwitch.liveTarget(
            presetRect: CGRect(x: 2700, y: 500, width: 800, height: 600),
            presetDisplayID: 7, presetMode: .hiddenWindow, activeMode: .hiddenWindow,
            currentRect: current, currentScreenID: 3, screens: screens))
    }

    func testVirtualDisplayNeedsMatchingAspect() {
        // 4:3 preset while sharing a 4:3 region → live switch.
        XCTAssertNotNil(PresetSwitch.liveTarget(
            presetRect: CGRect(x: 900, y: 200, width: 400, height: 300),
            presetDisplayID: 3, presetMode: .virtualDisplay, activeMode: .virtualDisplay,
            currentRect: current, currentScreenID: 3, screens: screens))
        // 16:9 preset while sharing 4:3 → restart.
        XCTAssertNil(PresetSwitch.liveTarget(
            presetRect: CGRect(x: 900, y: 200, width: 1600, height: 900),
            presetDisplayID: 3, presetMode: .virtualDisplay, activeMode: .virtualDisplay,
            currentRect: current, currentScreenID: 3, screens: screens))
    }
}

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
