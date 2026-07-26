import XCTest
@testable import RegionShare

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

    func testCapturePixelSizeFlooredToEven() {
        let s = Geometry.capturePixelSize(region: CGRect(x: 0, y: 0, width: 801.5, height: 599.5), scale: 1)
        XCTAssertEqual(s.width, 800)
        XCTAssertEqual(s.height, 598)
    }
}
