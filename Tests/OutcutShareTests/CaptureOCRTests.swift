import XCTest
@testable import OutcutShare

final class CaptureOCRTests: XCTestCase {
    // Vision boxes are normalized with a bottom-left origin: higher midY =
    // higher on screen.
    private func box(x: Double, y: Double) -> CGRect {
        CGRect(x: x, y: y, width: 0.2, height: 0.05)
    }

    func testJoinsTopToBottomLeftToRight() {
        let lines = [
            (text: "world", box: box(x: 0.4, y: 0.8)),
            (text: "bottom", box: box(x: 0.1, y: 0.2)),
            (text: "hello", box: box(x: 0.1, y: 0.8)),
        ]
        XCTAssertEqual(CaptureOCR.joined(lines), "hello world\nbottom")
    }

    func testSameRowToleratesSmallVerticalJitter() {
        let lines = [
            (text: "right", box: box(x: 0.5, y: 0.795)),
            (text: "left", box: box(x: 0.1, y: 0.81)),
        ]
        XCTAssertEqual(CaptureOCR.joined(lines), "left right")
    }

    func testEmptyInput() {
        XCTAssertEqual(CaptureOCR.joined([]), "")
    }
}

final class RecentCapturesTests: XCTestCase {
    func testAddingPutsNewestFirstAndCaps() {
        var list: [String] = []
        for index in 1...9 {
            list = RecentCaptures.updated(list, adding: "/tmp/f\(index)")
        }
        XCTAssertEqual(list.count, RecentCaptures.limit)
        XCTAssertEqual(list.first, "/tmp/f9")
        XCTAssertFalse(list.contains("/tmp/f1"))
    }

    func testAddingExistingMovesToFront() {
        let list = RecentCaptures.updated(["/a", "/b", "/c"], adding: "/b")
        XCTAssertEqual(list, ["/b", "/a", "/c"])
    }

    func testRemoving() {
        XCTAssertEqual(RecentCaptures.removing(["/a", "/b"], path: "/a"), ["/b"])
    }
}
