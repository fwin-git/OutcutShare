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

final class MonitorInteractionTests: XCTestCase {
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

    func testDragOutModifierDefaultsToShift() {
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.dragOutModifier, .shift)
    }

    func testDragOutModifierPersists() {
        let store = SettingsStore(defaults: defaults)
        store.dragOutModifier = .option
        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.dragOutModifier, .option)
    }

    func testModifierFlagMapping() {
        XCTAssertEqual(DragOutModifier.shift.flag, .shift)
        XCTAssertEqual(DragOutModifier.option.flag, .option)
        XCTAssertEqual(DragOutModifier.command.flag, .command)
        XCTAssertEqual(DragOutModifier.control.flag, .control)
    }

    func testResizeBandDetection() {
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 500)
        XCTAssertTrue(Geometry.isInResizeBand(CGPoint(x: 3, y: 250), bounds: bounds, band: 8))
        XCTAssertTrue(Geometry.isInResizeBand(CGPoint(x: 400, y: 495), bounds: bounds, band: 8))
        XCTAssertTrue(Geometry.isInResizeBand(CGPoint(x: 794, y: 4), bounds: bounds, band: 8))
        XCTAssertFalse(Geometry.isInResizeBand(CGPoint(x: 400, y: 250), bounds: bounds, band: 8))
        XCTAssertFalse(Geometry.isInResizeBand(CGPoint(x: 50, y: 50), bounds: bounds, band: 8))
    }

    func testCGPointConversion() {
        let p = Geometry.cgPoint(fromAppKit: CGPoint(x: 100, y: 400), primaryHeight: 1440)
        XCTAssertEqual(p, CGPoint(x: 100, y: 1040))
    }

    func testEdgeExitMapsPositionAlongTheHitEdge() {
        let display = CGRect(x: 5120, y: 0, width: 1920, height: 1080)
        let panel = CGRect(x: 1600, y: 180, width: 960, height: 540)

        // Left edge at 25% height → panel's left edge at 25% height.
        let left = Geometry.edgeExitPoint(mouse: CGPoint(x: 5121, y: 270),
                                          display: display, panel: panel, inset: 10)
        XCTAssertEqual(left.x, panel.minX + 10, accuracy: 0.01)
        XCTAssertEqual(left.y, panel.minY + 0.25 * panel.height, accuracy: 0.5)

        // Right edge mid-height → panel's right edge mid-height.
        let right = Geometry.edgeExitPoint(mouse: CGPoint(x: display.maxX - 1, y: 540),
                                           display: display, panel: panel, inset: 10)
        XCTAssertEqual(right.x, panel.maxX - 10, accuracy: 0.01)
        XCTAssertEqual(right.y, panel.midY, accuracy: 0.5)

        // Top edge at 75% width → panel's top edge at 75% width.
        let top = Geometry.edgeExitPoint(mouse: CGPoint(x: 5120 + 1440, y: display.maxY - 1),
                                         display: display, panel: panel, inset: 10)
        XCTAssertEqual(top.y, panel.maxY - 10, accuracy: 0.01)
        XCTAssertEqual(top.x, panel.minX + 0.75 * panel.width, accuracy: 0.5)

        // Bottom edge at 10% width → panel's bottom edge at 10% width.
        let bottom = Geometry.edgeExitPoint(mouse: CGPoint(x: 5120 + 192, y: 1),
                                            display: display, panel: panel, inset: 10)
        XCTAssertEqual(bottom.y, panel.minY + 10, accuracy: 0.01)
        XCTAssertEqual(bottom.x, panel.minX + 0.1 * panel.width, accuracy: 0.5)
    }

    func testDockSideDetection() {
        let frame = CGRect(x: 0, y: 0, width: 5120, height: 1440)
        XCTAssertEqual(Geometry.dockSide(
            frame: frame, visibleFrame: CGRect(x: 80, y: 0, width: 5040, height: 1415)),
            .left)
        XCTAssertEqual(Geometry.dockSide(
            frame: frame, visibleFrame: CGRect(x: 0, y: 0, width: 5040, height: 1415)),
            .right)
        XCTAssertEqual(Geometry.dockSide(
            frame: frame, visibleFrame: CGRect(x: 0, y: 80, width: 5120, height: 1335)),
            .bottom)
    }

    func testVirtualDisplayPlacedOppositeTheDock() {
        // Dock left → monitor to the right of the primary display.
        XCTAssertEqual(Geometry.virtualDisplayCGOrigin(primaryWidth: 5120,
                                                       monitorWidth: 1920,
                                                       dockSide: .left),
                       CGPoint(x: 5120, y: 0))
        // Dock right → monitor to the left.
        XCTAssertEqual(Geometry.virtualDisplayCGOrigin(primaryWidth: 5120,
                                                       monitorWidth: 1920,
                                                       dockSide: .right),
                       CGPoint(x: -1920, y: 0))
        // Bottom dock is safe on any side — default to the right.
        XCTAssertEqual(Geometry.virtualDisplayCGOrigin(primaryWidth: 5120,
                                                       monitorWidth: 1920,
                                                       dockSide: .bottom),
                       CGPoint(x: 5120, y: 0))
    }

    func testSeamlessExitContinuesTheMotionOutsideThePanel() {
        let display = CGRect(x: 5120, y: 0, width: 1920, height: 1080)
        let panel = CGRect(x: 1600, y: 180, width: 960, height: 540)
        let screen = CGRect(x: 0, y: 0, width: 5120, height: 1440)

        // Leftward push at 25% height: spawns LEFT of the panel, velocity
        // scaled to panel size (half here) carried through.
        let exit = Geometry.seamlessExitPoint(
            mouse: CGPoint(x: 5121, y: 270), previous: CGPoint(x: 5161, y: 260),
            display: display, panel: panel, screenBounds: screen)
        XCTAssertLessThan(exit.x, panel.minX)
        XCTAssertEqual(exit.x, panel.minX - 20, accuracy: 1) // vx −40 × 0.5
        XCTAssertEqual(exit.y, panel.minY + 0.25 * panel.height + 5, accuracy: 1)

        // No velocity: still guaranteed just outside the crossed edge.
        let still = Geometry.seamlessExitPoint(
            mouse: CGPoint(x: 5121, y: 540), previous: CGPoint(x: 5121, y: 540),
            display: display, panel: panel, screenBounds: screen)
        XCTAssertEqual(still.x, panel.minX - 6, accuracy: 0.01)

        // A violent flick is capped so the cursor doesn't fly across the room.
        let flick = Geometry.seamlessExitPoint(
            mouse: CGPoint(x: 5121, y: 540), previous: CGPoint(x: 5921, y: 540),
            display: display, panel: panel, screenBounds: screen)
        XCTAssertGreaterThanOrEqual(flick.x, panel.minX - 90 - 0.01)

        // Bottom edge: spawns below the panel.
        let bottom = Geometry.seamlessExitPoint(
            mouse: CGPoint(x: 5120 + 960, y: 1), previous: CGPoint(x: 5120 + 960, y: 41),
            display: display, panel: panel, screenBounds: screen)
        XCTAssertLessThan(bottom.y, panel.minY)
        XCTAssertEqual(bottom.x, panel.midX, accuracy: 1)

        // Never off the real screen.
        XCTAssertTrue(screen.contains(exit))
        XCTAssertTrue(screen.contains(bottom))
    }

    func testResizeEdgeMapping() {
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 500)
        XCTAssertEqual(Geometry.resizeEdge(for: CGPoint(x: 5, y: 250), bounds: bounds, band: 18), .left)
        XCTAssertEqual(Geometry.resizeEdge(for: CGPoint(x: 795, y: 250), bounds: bounds, band: 18), .right)
        XCTAssertEqual(Geometry.resizeEdge(for: CGPoint(x: 400, y: 495), bounds: bounds, band: 18), .top)
        XCTAssertEqual(Geometry.resizeEdge(for: CGPoint(x: 400, y: 5), bounds: bounds, band: 18), .bottom)
        // Corners resolve to the horizontal side (the aspect lock couples
        // the axes anyway).
        XCTAssertEqual(Geometry.resizeEdge(for: CGPoint(x: 5, y: 5), bounds: bounds, band: 18), .left)
        XCTAssertEqual(Geometry.resizeEdge(for: CGPoint(x: 795, y: 495), bounds: bounds, band: 18), .right)
        XCTAssertNil(Geometry.resizeEdge(for: CGPoint(x: 400, y: 250), bounds: bounds, band: 18))
    }
}

final class SnapTileTests: XCTestCase {
    func testEdgeZonesGiveHalves() {
        XCTAssertEqual(Geometry.snapTileUnit(for: CGPoint(x: 0.05, y: 0.5)),
                       CGRect(x: 0, y: 0, width: 0.5, height: 1))
        XCTAssertEqual(Geometry.snapTileUnit(for: CGPoint(x: 0.95, y: 0.5)),
                       CGRect(x: 0.5, y: 0, width: 0.5, height: 1))
    }

    func testTopCenterGivesFullScreen() {
        XCTAssertEqual(Geometry.snapTileUnit(for: CGPoint(x: 0.5, y: 0.95)),
                       CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    func testCornersGiveQuarters() {
        XCTAssertEqual(Geometry.snapTileUnit(for: CGPoint(x: 0.05, y: 0.95)),
                       CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5))
        XCTAssertEqual(Geometry.snapTileUnit(for: CGPoint(x: 0.95, y: 0.05)),
                       CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5))
    }

    func testCenterIsFreePlacement() {
        XCTAssertNil(Geometry.snapTileUnit(for: CGPoint(x: 0.5, y: 0.5)))
        XCTAssertNil(Geometry.snapTileUnit(for: CGPoint(x: 0.3, y: 0.7)))
    }

    func testUnitRectScalesIntoTarget() {
        let target = CGRect(x: 5120, y: 0, width: 1920, height: 1080)
        let scaled = Geometry.rectByScaling(unit: CGRect(x: 0.5, y: 0, width: 0.5, height: 1),
                                            into: target)
        XCTAssertEqual(scaled, CGRect(x: 5120 + 960, y: 0, width: 960, height: 1080))
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
