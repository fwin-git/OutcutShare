import XCTest
@testable import OutcutShare

final class SnappingTests: XCTestCase {
    func testAppKitRectFromCGTopLeft() {
        // Primary display 2560x1440: CG top-left origin → AppKit bottom-left.
        let cg = CGRect(x: 100, y: 200, width: 800, height: 600)
        let converted = Geometry.appKitRect(fromCGTopLeft: cg, primaryHeight: 1440)
        XCTAssertEqual(converted, CGRect(x: 100, y: 640, width: 800, height: 600))
    }

    func testPresetCandidatesAnchoredTowardDragDirection() {
        let bounds = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let candidates = Geometry.presetCandidates(anchor: CGPoint(x: 100, y: 1300),
                                                   toward: CGPoint(x: 400, y: 1000),
                                                   sizes: [CGSize(width: 1280, height: 720)],
                                                   bounds: bounds)
        // Dragging right+down from near the top: rect extends right and down.
        XCTAssertEqual(candidates, [CGRect(x: 100, y: 580, width: 1280, height: 720)])
    }

    func testPresetCandidatesSkipNonFittingSizes() {
        let bounds = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let candidates = Geometry.presetCandidates(anchor: CGPoint(x: 2000, y: 700),
                                                   toward: CGPoint(x: 2100, y: 800),
                                                   sizes: [CGSize(width: 1280, height: 720),
                                                           CGSize(width: 320, height: 240)],
                                                   bounds: bounds)
        // Only 560pt of room to the right: 1280-wide can't fit, 320 can.
        XCTAssertEqual(candidates, [nil, CGRect(x: 2000, y: 700, width: 320, height: 240)])
    }

    func testSnappedPresetPicksNearestFarCorner() {
        let a = CGRect(x: 0, y: 0, width: 1280, height: 720)
        let b = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let index = Geometry.snappedPresetIndex(dragged: CGPoint(x: 1800, y: 1000),
                                                candidates: [a, b],
                                                anchor: .zero)
        XCTAssertEqual(index, 1)
        let indexSmall = Geometry.snappedPresetIndex(dragged: CGPoint(x: 1100, y: 700),
                                                     candidates: [a, b],
                                                     anchor: .zero)
        XCTAssertEqual(indexSmall, 0)
        XCTAssertNil(Geometry.snappedPresetIndex(dragged: .zero, candidates: [], anchor: .zero))
    }

    func testEdgeResizeRightAndLeft() {
        let screen = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let region = CGRect(x: 500, y: 500, width: 600, height: 400)
        let wider = Geometry.edgeResizedRegion(region, edge: .right,
                                               draggedTo: CGPoint(x: 1400, y: 0),
                                               lockedAspect: nil, screenFrame: screen)
        XCTAssertEqual(wider, CGRect(x: 500, y: 500, width: 900, height: 400))
        let narrowerLeft = Geometry.edgeResizedRegion(region, edge: .left,
                                                      draggedTo: CGPoint(x: 700, y: 0),
                                                      lockedAspect: nil, screenFrame: screen)
        XCTAssertEqual(narrowerLeft, CGRect(x: 700, y: 500, width: 400, height: 400))
    }

    func testEdgeResizeEnforcesMinimumAndScreenBounds() {
        let screen = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let region = CGRect(x: 500, y: 500, width: 600, height: 400)
        // Dragging the right edge past the left side clamps at the minimum.
        let tiny = Geometry.edgeResizedRegion(region, edge: .right,
                                              draggedTo: CGPoint(x: 100, y: 0),
                                              lockedAspect: nil, screenFrame: screen)
        XCTAssertEqual(tiny.width, Geometry.minRegionSide)
        // Dragging the top edge beyond the screen clamps to the screen.
        let tall = Geometry.edgeResizedRegion(region, edge: .top,
                                              draggedTo: CGPoint(x: 0, y: 2000),
                                              lockedAspect: nil, screenFrame: screen)
        XCTAssertEqual(tall.maxY, 1440)
    }

    func testEdgeResizeWithAspectKeepsCrossAxisCentered() {
        let screen = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let region = CGRect(x: 500, y: 500, width: 600, height: 400)
        let resized = Geometry.edgeResizedRegion(region, edge: .right,
                                                 draggedTo: CGPoint(x: 1300, y: 0),
                                                 lockedAspect: 2.0, screenFrame: screen)
        XCTAssertEqual(resized.width, 800, accuracy: 0.01)
        XCTAssertEqual(resized.height, 400, accuracy: 0.01)
        XCTAssertEqual(resized.midY, region.midY, accuracy: 0.01) // centered vertically
        XCTAssertEqual(resized.minX, 500, accuracy: 0.01)          // left edge fixed
    }

    func testFrontmostWindowFrameAtPoint() {
        let front = CGRect(x: 100, y: 100, width: 400, height: 300)
        let back = CGRect(x: 50, y: 50, width: 900, height: 700)
        // List is front-to-back; both contain the point → front wins.
        XCTAssertEqual(Geometry.frontmostWindowFrame(at: CGPoint(x: 200, y: 200),
                                                     windows: [front, back]), front)
        // Point only inside the back window.
        XCTAssertEqual(Geometry.frontmostWindowFrame(at: CGPoint(x: 60, y: 60),
                                                     windows: [front, back]), back)
        XCTAssertNil(Geometry.frontmostWindowFrame(at: CGPoint(x: 5000, y: 5000),
                                                   windows: [front, back]))
    }
}
