import XCTest
@testable import OutcutShare

final class HotbarPositionTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 2560, height: 1440)
    private let bar = CGSize(width: 340, height: 44)
    private let gap: CGFloat = 12

    func testPrefersBelowCentered() {
        let region = CGRect(x: 800, y: 500, width: 800, height: 600)
        let origin = Geometry.hotbarOrigin(barSize: bar, region: region,
                                           screenFrame: screen, gap: gap)
        XCTAssertEqual(origin, CGPoint(x: 1200 - 170, y: 500 - 12 - 44))
    }

    func testFallsBackToRightSideWhenNoSpaceBelow() {
        let region = CGRect(x: 800, y: 10, width: 800, height: 600)
        let origin = Geometry.hotbarOrigin(barSize: bar, region: region,
                                           screenFrame: screen, gap: gap)
        XCTAssertEqual(origin.x, region.maxX + gap)
        XCTAssertEqual(origin.y, region.midY - bar.height / 2)
    }

    func testFallsBackToLeftSideWhenNoSpaceRight() {
        let region = CGRect(x: 1900, y: 10, width: 650, height: 600)
        let origin = Geometry.hotbarOrigin(barSize: bar, region: region,
                                           screenFrame: screen, gap: gap)
        XCTAssertEqual(origin.x, region.minX - gap - bar.width)
    }

    func testFallsBackToTopWhenOnlySpaceAbove() {
        let region = CGRect(x: 100, y: 0, width: 2360, height: 600)
        let origin = Geometry.hotbarOrigin(barSize: bar, region: region,
                                           screenFrame: screen, gap: gap)
        XCTAssertEqual(origin.y, region.maxY + gap)
    }

    func testFullScreenRegionFallsBackInsideBottom() {
        let region = screen
        let origin = Geometry.hotbarOrigin(barSize: bar, region: region,
                                           screenFrame: screen, gap: gap)
        XCTAssertEqual(origin.y, region.minY + gap)
        XCTAssertTrue(screen.contains(CGRect(origin: origin, size: bar)))
    }

    func testHorizontalClampingToScreen() {
        // Region hugging the left edge: centered-below would go off screen.
        let region = CGRect(x: 0, y: 500, width: 100, height: 400)
        let origin = Geometry.hotbarOrigin(barSize: bar, region: region,
                                           screenFrame: screen, gap: gap)
        XCTAssertEqual(origin.x, 0)
        XCTAssertEqual(origin.y, 500 - 12 - 44)
    }

    func testHotbarSideMatchesPlacementPreference() {
        XCTAssertEqual(Geometry.hotbarSide(barSize: bar,
                                           region: CGRect(x: 800, y: 500, width: 800, height: 600),
                                           screenFrame: screen, gap: gap), .below)
        XCTAssertEqual(Geometry.hotbarSide(barSize: bar,
                                           region: CGRect(x: 800, y: 10, width: 800, height: 600),
                                           screenFrame: screen, gap: gap), .right)
        XCTAssertEqual(Geometry.hotbarSide(barSize: bar,
                                           region: CGRect(x: 1900, y: 10, width: 650, height: 600),
                                           screenFrame: screen, gap: gap), .left)
        XCTAssertEqual(Geometry.hotbarSide(barSize: bar,
                                           region: CGRect(x: 100, y: 0, width: 2360, height: 600),
                                           screenFrame: screen, gap: gap), .above)
        XCTAssertEqual(Geometry.hotbarSide(barSize: bar, region: screen,
                                           screenFrame: screen, gap: gap), .inside)
    }

    func testFixedSideOriginForVerticalBar() {
        // A vertical bar (swapped footprint) pinned to the right edge of a
        // region that only has side space: x at the edge, y centered.
        let vertical = CGSize(width: 44, height: 340)
        let region = CGRect(x: 800, y: 10, width: 800, height: 600)
        let origin = Geometry.hotbarOrigin(barSize: vertical, region: region,
                                           screenFrame: screen, gap: gap, side: .right)
        XCTAssertEqual(origin.x, region.maxX + gap)
        XCTAssertEqual(origin.y, region.midY - vertical.height / 2)
        // Same bar forced below (manual orientation override): y below region.
        let below = Geometry.hotbarOrigin(barSize: vertical, region: region,
                                          screenFrame: screen, gap: gap, side: .below)
        XCTAssertEqual(below.y, max(screen.minY, region.minY - gap - vertical.height))
    }
}
