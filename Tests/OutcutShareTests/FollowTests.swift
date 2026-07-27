import XCTest
@testable import OutcutShare

final class FollowTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 2560, height: 1440)

    func testAspectFittedRectWithoutAspectMatchesTarget() {
        let window = CGRect(x: 300, y: 300, width: 900, height: 700)
        let fitted = Geometry.aspectFittedRect(around: window, aspect: nil, screenFrame: screen)
        XCTAssertEqual(fitted, window)
    }

    func testAspectFittedRectGrowsToCoverTarget() {
        // 4:3 aspect around a tall window: width grows to keep the aspect.
        let window = CGRect(x: 500, y: 200, width: 600, height: 900)
        let fitted = Geometry.aspectFittedRect(around: window, aspect: 4.0 / 3.0, screenFrame: screen)
        XCTAssertEqual(fitted.width, 1200, accuracy: 0.01)
        XCTAssertEqual(fitted.height, 900, accuracy: 0.01)
        // Centered on the window's center.
        XCTAssertEqual(fitted.midX, window.midX, accuracy: 0.01)
        XCTAssertEqual(fitted.midY, window.midY, accuracy: 0.01)
    }

    func testAspectFittedRectShrinksAndClampsToScreen() {
        let window = CGRect(x: -200, y: -100, width: 4000, height: 2000)
        let fitted = Geometry.aspectFittedRect(around: window, aspect: nil, screenFrame: screen)
        XCTAssertEqual(fitted, screen)
        let fittedAspect = Geometry.aspectFittedRect(around: window, aspect: 2.0, screenFrame: screen)
        XCTAssertEqual(fittedAspect.width / fittedAspect.height, 2.0, accuracy: 0.001)
        XCTAssertTrue(screen.contains(fittedAspect))
    }

    func testDeadZoneShiftZeroInsideInnerRegion() {
        let region = CGRect(x: 500, y: 500, width: 600, height: 400)
        XCTAssertEqual(Geometry.deadZoneShift(region: region,
                                              point: CGPoint(x: 800, y: 700), margin: 80),
                       .zero)
    }

    func testDeadZoneShiftPushesTowardPoint() {
        let region = CGRect(x: 500, y: 500, width: 600, height: 400)
        // Point 30pt beyond the right inner edge (inner maxX = 1100-80 = 1020).
        let shift = Geometry.deadZoneShift(region: region,
                                           point: CGPoint(x: 1050, y: 700), margin: 80)
        XCTAssertEqual(shift, CGSize(width: 30, height: 0))
        // Below the bottom inner edge (inner minY = 580).
        let down = Geometry.deadZoneShift(region: region,
                                          point: CGPoint(x: 800, y: 560), margin: 80)
        XCTAssertEqual(down, CGSize(width: 0, height: -20))
    }

    func testDeadZoneMarginCappedForSmallRegions() {
        // Margin larger than a third of the region must not invert the inner rect.
        let region = CGRect(x: 0, y: 0, width: 120, height: 120)
        let shift = Geometry.deadZoneShift(region: region,
                                           point: CGPoint(x: 60, y: 60), margin: 80)
        XCTAssertEqual(shift, .zero)
    }
}
