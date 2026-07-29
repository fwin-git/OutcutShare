import XCTest
@testable import OutcutShare

final class PreviewPanelGeometryTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 2560, height: 1440)

    func testDefaultPlacementBottomRight() {
        let f = Geometry.previewPanelFrame(aspect: 16.0 / 9.0, screenFrame: screen)
        XCTAssertEqual(f.maxX, 2560 - 16)
        XCTAssertEqual(f.minY, 16)
        XCTAssertEqual(f.width, 320)
        XCTAssertEqual(f.height, 180, accuracy: 0.01)
    }

    func testTallAspectIsHeightLimited() {
        let small = CGRect(x: 0, y: 0, width: 800, height: 400)
        let f = Geometry.previewPanelFrame(aspect: 0.5, screenFrame: small)
        XCTAssertEqual(f.height, 400 - 32)
        XCTAssertEqual(f.width, f.height * 0.5, accuracy: 0.01)
        XCTAssertTrue(small.contains(f))
    }

    func testRefitKeepsWidthAndTopEdge() {
        let current = CGRect(x: 100, y: 500, width: 320, height: 180)
        let f = Geometry.aspectRefittedPanelFrame(current: current, aspect: 1.0,
                                                 screenFrame: screen)
        XCTAssertEqual(f.width, 320)
        XCTAssertEqual(f.height, 320)
        XCTAssertEqual(f.maxY, current.maxY)
        XCTAssertEqual(f.minX, 100)
    }

    func testRefitClampsInsideScreen() {
        let current = CGRect(x: 2300, y: 20, width: 320, height: 180)
        let f = Geometry.aspectRefittedPanelFrame(current: current, aspect: 1.0,
                                                 screenFrame: screen)
        XCTAssertTrue(screen.contains(f))
        XCTAssertEqual(f.height, 320)
    }

    func testRefitEnforcesMinWidth() {
        let current = CGRect(x: 100, y: 500, width: 40, height: 30)
        let f = Geometry.aspectRefittedPanelFrame(current: current, aspect: 2.0,
                                                 screenFrame: screen)
        XCTAssertEqual(f.width, 160)
        XCTAssertEqual(f.height, 80)
    }

    func testRefitShrinksOversizedAspectToScreen() {
        let tiny = CGRect(x: 0, y: 0, width: 500, height: 300)
        let current = CGRect(x: 0, y: 0, width: 480, height: 100)
        let f = Geometry.aspectRefittedPanelFrame(current: current, aspect: 1.0,
                                                 screenFrame: tiny)
        XCTAssertTrue(tiny.contains(f))
        XCTAssertEqual(f.width, f.height, accuracy: 0.01)
    }
}

final class PreviewDockingTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 2560, height: 1440)
    private let size = CGSize(width: 320, height: 200)
    private let gap: CGFloat = 12

    func testDocksRightOfRegionBottomAligned() {
        let region = CGRect(x: 600, y: 400, width: 800, height: 500)
        let f = Geometry.previewDockedFrame(size: size, region: region, screenFrame: screen)
        XCTAssertEqual(f.minX, region.maxX + gap)
        XCTAssertEqual(f.minY, region.minY)
        XCTAssertFalse(f.intersects(region))
    }

    func testFallsBackToLeftWhenNoSpaceRight() {
        let region = CGRect(x: 1500, y: 400, width: 1000, height: 500)
        let f = Geometry.previewDockedFrame(size: size, region: region, screenFrame: screen)
        XCTAssertEqual(f.maxX, region.minX - gap)
        XCTAssertEqual(f.minY, region.minY)
    }

    func testFallsBackBelowRightAlignedWhenNoSideSpace() {
        let region = CGRect(x: 100, y: 400, width: 2360, height: 500)
        let f = Geometry.previewDockedFrame(size: size, region: region, screenFrame: screen)
        XCTAssertEqual(f.maxX, region.maxX)
        XCTAssertEqual(f.maxY, region.minY - gap)
    }

    func testFallsBackAboveWhenOnlySpaceOnTop() {
        let region = CGRect(x: 100, y: 0, width: 2360, height: 500)
        let f = Geometry.previewDockedFrame(size: size, region: region, screenFrame: screen)
        XCTAssertEqual(f.maxX, region.maxX)
        XCTAssertEqual(f.minY, region.maxY + gap)
    }

    func testNearFullscreenRegionFallsBackToScreenCorner() {
        let region = screen.insetBy(dx: 10, dy: 10)
        let f = Geometry.previewDockedFrame(size: size, region: region, screenFrame: screen)
        XCTAssertEqual(f.maxX, screen.maxX - 16)
        XCTAssertEqual(f.minY, screen.minY + 16)
    }
}

final class PreviewSettingsTests: XCTestCase {
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

    func testPreviewOffByDefault() {
        let store = SettingsStore(defaults: defaults)
        XCTAssertFalse(store.previewWindowEnabled)
    }

    func testPreviewPersistence() {
        let store = SettingsStore(defaults: defaults)
        store.previewWindowEnabled = true

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertTrue(reloaded.previewWindowEnabled)
    }

    func testShareWindowTitleDefault() {
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.shareWindowTitle, SettingsStore.defaultShareWindowTitle)
        XCTAssertEqual(store.effectiveShareWindowTitle, SettingsStore.defaultShareWindowTitle)
    }

    func testShareWindowTitlePersistence() {
        let store = SettingsStore(defaults: defaults)
        store.shareWindowTitle = "Weekly Demo"

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.shareWindowTitle, "Weekly Demo")
        XCTAssertEqual(reloaded.effectiveShareWindowTitle, "Weekly Demo")
    }

    func testEmptyShareWindowTitleFallsBackToDefault() {
        let store = SettingsStore(defaults: defaults)
        store.shareWindowTitle = "   "
        XCTAssertEqual(store.effectiveShareWindowTitle, SettingsStore.defaultShareWindowTitle)
    }
}
