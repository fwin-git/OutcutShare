import XCTest
@testable import OutcutShare

final class TrimMathTests: XCTestCase {
    func testClampInKeepsGapToOut() {
        XCTAssertEqual(TrimMath.clampedIn(0.5, out: 0.6, minGap: 0.2), 0.4, accuracy: 1e-9)
        XCTAssertEqual(TrimMath.clampedIn(0.1, out: 0.9, minGap: 0.2), 0.1)
        XCTAssertEqual(TrimMath.clampedIn(-0.3, out: 0.9, minGap: 0.2), 0)
    }

    func testClampOutKeepsGapToIn() {
        XCTAssertEqual(TrimMath.clampedOut(0.5, in: 0.4, minGap: 0.2), 0.6, accuracy: 1e-9)
        XCTAssertEqual(TrimMath.clampedOut(0.9, in: 0.1, minGap: 0.2), 0.9)
        XCTAssertEqual(TrimMath.clampedOut(1.4, in: 0.1, minGap: 0.2), 1)
    }

    func testMinGapLargerThanRangeStillOrdersHandles() {
        // Gap can't be honored in a tiny range — in pins to 0, out to 1.
        XCTAssertEqual(TrimMath.clampedIn(0.9, out: 0.5, minGap: 2), 0)
        XCTAssertEqual(TrimMath.clampedOut(0.1, in: 0.5, minGap: 2), 1)
    }

    func testTimeString() {
        XCTAssertEqual(TrimMath.timeString(0), "0:00")
        XCTAssertEqual(TrimMath.timeString(7.4), "0:07")
        XCTAssertEqual(TrimMath.timeString(65), "1:05")
        XCTAssertEqual(TrimMath.timeString(3671), "1:01:11")
    }
}

final class UniqueSiblingTests: XCTestCase {
    func testAppendsSuffixBeforeExtension() {
        let url = URL(fileURLWithPath: "/tmp/recs/recording_2026-07-29_10-12.mp4")
        let sibling = CaptureNaming.uniqueSibling(of: url, suffix: "_trim") { _ in false }
        XCTAssertEqual(sibling.path, "/tmp/recs/recording_2026-07-29_10-12_trim.mp4")
    }

    func testCountsUpOnCollision() {
        let url = URL(fileURLWithPath: "/tmp/recs/clip.mp4")
        let taken = ["/tmp/recs/clip_trim.mp4", "/tmp/recs/clip_trim_2.mp4"]
        let sibling = CaptureNaming.uniqueSibling(of: url, suffix: "_trim") {
            taken.contains($0.path)
        }
        XCTAssertEqual(sibling.path, "/tmp/recs/clip_trim_3.mp4")
    }
}
