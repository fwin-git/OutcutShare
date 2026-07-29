import XCTest
@testable import OutcutShare

final class CaptureNamingTests: XCTestCase {
    // Built in the current calendar/timezone — CaptureNaming formats in
    // local time, so the components must round-trip on any CI machine.
    private let date = Calendar.current
        .date(from: DateComponents(year: 2026, month: 7, day: 29,
                                   hour: 9, minute: 5))!

    func testScreenshotNameFormat() {
        XCTAssertEqual(CaptureNaming.fileName(prefix: "screenshot", date: date, ext: "png"),
                       "screenshot_2026-07-29_09-05.png")
    }

    func testRecordingNameFormat() {
        XCTAssertEqual(CaptureNaming.fileName(prefix: "recording", date: date, ext: "mp4"),
                       "recording_2026-07-29_09-05.mp4")
    }

    func testUniqueNameAppendsCounterOnCollision() {
        let taken = ["screenshot_2026-07-29_09-05.png",
                     "screenshot_2026-07-29_09-05_2.png"]
        let name = CaptureNaming.uniqueFileName(prefix: "screenshot", date: date,
                                                ext: "png") { taken.contains($0) }
        XCTAssertEqual(name, "screenshot_2026-07-29_09-05_3.png")
    }

    func testUniqueNameWithoutCollisionKeepsBase() {
        let name = CaptureNaming.uniqueFileName(prefix: "screenshot", date: date,
                                                ext: "png") { _ in false }
        XCTAssertEqual(name, "screenshot_2026-07-29_09-05.png")
    }
}
