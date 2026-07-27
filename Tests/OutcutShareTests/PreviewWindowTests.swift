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
        XCTAssertFalse(store.previewWindowPinned)
    }

    func testPreviewPersistence() {
        let store = SettingsStore(defaults: defaults)
        store.previewWindowEnabled = true
        store.previewWindowPinned = true

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertTrue(reloaded.previewWindowEnabled)
        XCTAssertTrue(reloaded.previewWindowPinned)
    }
}
