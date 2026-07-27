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

final class MonitorDragGeometryTests: XCTestCase {
    private let panel = CGRect(x: 1600, y: 180, width: 1920, height: 1080)
    private let display = CGRect(x: 5120, y: 0, width: 1920, height: 1080)

    func testPreviewPointMapsLinearlyOntoDisplay() {
        let center = Geometry.previewPointToDisplayPoint(
            CGPoint(x: panel.midX, y: panel.midY), panel: panel, display: display)
        XCTAssertEqual(center.x, display.midX, accuracy: 0.01)
        XCTAssertEqual(center.y, display.midY, accuracy: 0.01)

        let corner = Geometry.previewPointToDisplayPoint(
            CGPoint(x: panel.minX, y: panel.minY), panel: panel, display: display)
        XCTAssertEqual(corner, display.origin)
    }

    func testCenteredClampedWindowOrigin() {
        let origin = Geometry.centeredClampedWindowOrigin(
            size: CGSize(width: 400, height: 300),
            center: CGPoint(x: display.minX + 50, y: display.minY + 50), bounds: display)
        XCTAssertEqual(origin, display.origin) // clamped into the corner
        let free = Geometry.centeredClampedWindowOrigin(
            size: CGSize(width: 400, height: 300),
            center: CGPoint(x: display.midX, y: display.midY), bounds: display)
        XCTAssertEqual(free.x, display.midX - 200, accuracy: 0.01)
        XCTAssertEqual(free.y, display.midY - 150, accuracy: 0.01)
    }

    func testCGTopLeftPointConversion() {
        // AppKit rect on a 1440-tall primary: top edge at y=1000 → CG y = 440.
        let p = Geometry.cgTopLeftPoint(forAppKit: CGRect(x: 10, y: 600, width: 100, height: 400),
                                        primaryHeight: 1440)
        XCTAssertEqual(p, CGPoint(x: 10, y: 440))
    }

    func testDropRequiresEndInsidePanelAndRealWindowMovement() {
        let start = CGPoint(x: 400, y: 400)
        let inside = CGPoint(x: panel.midX, y: panel.midY)
        let movedFrame = CGRect(x: 500, y: 450, width: 600, height: 400)
        let unmovedFrame = CGRect(x: 100, y: 100, width: 600, height: 400)

        XCTAssertTrue(Geometry.isWindowDropOnPanel(
            start: start, end: inside, panel: panel,
            windowFrameAtStart: unmovedFrame, windowFrameAtEnd: movedFrame))
        // Ended outside the panel.
        XCTAssertFalse(Geometry.isWindowDropOnPanel(
            start: start, end: CGPoint(x: 100, y: 100), panel: panel,
            windowFrameAtStart: unmovedFrame, windowFrameAtEnd: movedFrame))
        // Window never moved: just a click-through, not a window drag.
        XCTAssertFalse(Geometry.isWindowDropOnPanel(
            start: start, end: inside, panel: panel,
            windowFrameAtStart: unmovedFrame, windowFrameAtEnd: unmovedFrame))
        // Tiny drag distance.
        XCTAssertFalse(Geometry.isWindowDropOnPanel(
            start: CGPoint(x: panel.midX + 5, y: panel.midY), end: inside, panel: panel,
            windowFrameAtStart: unmovedFrame, windowFrameAtEnd: movedFrame))
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
