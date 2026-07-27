import XCTest
@testable import OutcutShare

final class GeometryTests: XCTestCase {
    func testSelectionRectFromAnyCornerOrder() {
        let expected = CGRect(x: 10, y: 20, width: 30, height: 40)
        let drags: [(CGPoint, CGPoint)] = [
            (CGPoint(x: 10, y: 20), CGPoint(x: 40, y: 60)),
            (CGPoint(x: 40, y: 60), CGPoint(x: 10, y: 20)),
            (CGPoint(x: 10, y: 60), CGPoint(x: 40, y: 20)),
            (CGPoint(x: 40, y: 20), CGPoint(x: 10, y: 60)),
        ]
        for (a, b) in drags {
            XCTAssertEqual(Geometry.selectionRect(from: a, to: b), expected)
        }
    }

    func testMinimumSize() {
        XCTAssertFalse(Geometry.meetsMinimumSize(CGRect(x: 0, y: 0, width: 63, height: 100)))
        XCTAssertFalse(Geometry.meetsMinimumSize(CGRect(x: 0, y: 0, width: 100, height: 63)))
        XCTAssertTrue(Geometry.meetsMinimumSize(CGRect(x: 0, y: 0, width: 64, height: 64)))
    }

    func testDisplayLocalTopLeftRectOnMainScreen() {
        let screen = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let region = CGRect(x: 100, y: 200, width: 800, height: 600)
        let local = Geometry.displayLocalTopLeftRect(appKitGlobal: region, screenFrame: screen)
        XCTAssertEqual(local, CGRect(x: 100, y: 640, width: 800, height: 600))
    }

    func testDisplayLocalTopLeftRectOnSecondaryScreen() {
        let screen = CGRect(x: 2560, y: 360, width: 1920, height: 1080)
        let region = CGRect(x: 2660, y: 460, width: 400, height: 300)
        let local = Geometry.displayLocalTopLeftRect(appKitGlobal: region, screenFrame: screen)
        XCTAssertEqual(local, CGRect(x: 100, y: 680, width: 400, height: 300))
    }

    func testCapturePixelSizeScales() {
        let s = Geometry.capturePixelSize(region: CGRect(x: 0, y: 0, width: 801, height: 600), scale: 2)
        XCTAssertEqual(s.width, 1602)
        XCTAssertEqual(s.height, 1200)
    }

    func testHiddenWindowFrameKeepsOnePixelOnScreen() {
        let screen = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let frame = Geometry.hiddenWindowFrame(regionSize: CGSize(width: 400, height: 300),
                                               screenFrame: screen)
        XCTAssertEqual(frame, CGRect(x: 2559, y: -299, width: 400, height: 300))
        // Exactly 1x1 px intersects the screen.
        let intersection = frame.intersection(screen)
        XCTAssertEqual(intersection.size, CGSize(width: 1, height: 1))
    }

    func testHiddenWindowFrameOnOffsetScreen() {
        let screen = CGRect(x: 2560, y: 360, width: 1920, height: 1080)
        let frame = Geometry.hiddenWindowFrame(regionSize: CGSize(width: 640, height: 480),
                                               screenFrame: screen)
        XCTAssertEqual(frame, CGRect(x: 4479, y: -119, width: 640, height: 480))
        XCTAssertEqual(frame.intersection(screen).size, CGSize(width: 1, height: 1))
    }

    func testClampedRegionOriginInsideScreenUnchanged() {
        let screen = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let origin = Geometry.clampedRegionOrigin(CGPoint(x: 300, y: 400),
                                                  regionSize: CGSize(width: 800, height: 600),
                                                  screenFrame: screen)
        XCTAssertEqual(origin, CGPoint(x: 300, y: 400))
    }

    func testClampedRegionOriginClampsToEdges() {
        let screen = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let size = CGSize(width: 800, height: 600)
        XCTAssertEqual(Geometry.clampedRegionOrigin(CGPoint(x: -50, y: -20),
                                                    regionSize: size, screenFrame: screen),
                       CGPoint(x: 0, y: 0))
        XCTAssertEqual(Geometry.clampedRegionOrigin(CGPoint(x: 2400, y: 1200),
                                                    regionSize: size, screenFrame: screen),
                       CGPoint(x: 1760, y: 840))
    }

    func testClampedRegionOriginOnOffsetScreen() {
        let screen = CGRect(x: 2560, y: 360, width: 1920, height: 1080)
        let origin = Geometry.clampedRegionOrigin(CGPoint(x: 100, y: 100),
                                                  regionSize: CGSize(width: 640, height: 480),
                                                  screenFrame: screen)
        XCTAssertEqual(origin, CGPoint(x: 2560, y: 360))
    }

    func testResizedRegionFree() {
        let screen = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let rect = Geometry.resizedRegion(anchor: CGPoint(x: 100, y: 100),
                                          dragged: CGPoint(x: 700, y: 500),
                                          aspect: nil, screenFrame: screen)
        XCTAssertEqual(rect, CGRect(x: 100, y: 100, width: 600, height: 400))
        // Dragging left/below the anchor grows the rect in that direction.
        let flipped = Geometry.resizedRegion(anchor: CGPoint(x: 700, y: 500),
                                             dragged: CGPoint(x: 100, y: 100),
                                             aspect: nil, screenFrame: screen)
        XCTAssertEqual(flipped, CGRect(x: 100, y: 100, width: 600, height: 400))
    }

    func testResizedRegionEnforcesMinimumSize() {
        let screen = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let rect = Geometry.resizedRegion(anchor: CGPoint(x: 100, y: 100),
                                          dragged: CGPoint(x: 110, y: 105),
                                          aspect: nil, screenFrame: screen)
        XCTAssertEqual(rect.size, CGSize(width: 64, height: 64))
        XCTAssertEqual(rect.origin, CGPoint(x: 100, y: 100))
    }

    func testResizedRegionAspectConstraintUsesDominantAxis() {
        let screen = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        // Aspect 4:3; drag spans 1200x600 → width dominates → 1200x900.
        let wide = Geometry.resizedRegion(anchor: CGPoint(x: 100, y: 100),
                                          dragged: CGPoint(x: 1300, y: 700),
                                          aspect: 4.0 / 3.0, screenFrame: screen)
        XCTAssertEqual(wide, CGRect(x: 100, y: 100, width: 1200, height: 900))
        // Drag spans 400x900 → height dominates → 1200x900.
        let tall = Geometry.resizedRegion(anchor: CGPoint(x: 100, y: 100),
                                          dragged: CGPoint(x: 500, y: 1000),
                                          aspect: 4.0 / 3.0, screenFrame: screen)
        XCTAssertEqual(tall, CGRect(x: 100, y: 100, width: 1200, height: 900))
    }

    func testResizedRegionClampsToScreen() {
        let screen = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let free = Geometry.resizedRegion(anchor: CGPoint(x: 2000, y: 1000),
                                          dragged: CGPoint(x: 3000, y: 2000),
                                          aspect: nil, screenFrame: screen)
        XCTAssertEqual(free, CGRect(x: 2000, y: 1000, width: 560, height: 440))
        // With aspect 2:1 the screen-limited height also limits the width.
        let constrained = Geometry.resizedRegion(anchor: CGPoint(x: 2000, y: 1000),
                                                 dragged: CGPoint(x: 3000, y: 2000),
                                                 aspect: 2, screenFrame: screen)
        XCTAssertEqual(constrained, CGRect(x: 2000, y: 1000, width: 560, height: 280))
    }

    func testCapturePixelSizeFlooredToEven() {
        let s = Geometry.capturePixelSize(region: CGRect(x: 0, y: 0, width: 801.5, height: 599.5), scale: 1)
        XCTAssertEqual(s.width, 800)
        XCTAssertEqual(s.height, 598)
    }
}
