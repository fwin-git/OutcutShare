import XCTest
@testable import OutcutShare

final class URLCommandsTests: XCTestCase {
    private func parse(_ s: String) -> URLCommand? {
        URLCommand.parse(URL(string: s)!)
    }

    func testSimpleCommands() {
        XCTAssertEqual(parse("outcutshare://select"), .select)
        XCTAssertEqual(parse("outcutshare://share-last"), .shareLast)
        XCTAssertEqual(parse("outcutshare://stop"), .stop)
        XCTAssertEqual(parse("outcutshare://pause"), .togglePause)
        XCTAssertEqual(parse("outcutshare://record"), .toggleRecording)
    }

    func testCommandNameIsCaseInsensitive() {
        XCTAssertEqual(parse("outcutshare://Share-Last"), .shareLast)
    }

    func testPresetRequiresIdOrName() {
        XCTAssertEqual(parse("outcutshare://preset?id=ABC"), .preset(id: "ABC", name: nil))
        XCTAssertEqual(parse("outcutshare://preset?name=Demo"), .preset(id: nil, name: "Demo"))
        XCTAssertEqual(parse("outcutshare://preset?id=ABC&name=Demo"),
                       .preset(id: "ABC", name: "Demo"))
        XCTAssertNil(parse("outcutshare://preset"))
    }

    func testPresetNameIsPercentDecoded() {
        XCTAssertEqual(parse("outcutshare://preset?name=Left%20Half"),
                       .preset(id: nil, name: "Left Half"))
    }

    func testFollowModes() {
        XCTAssertEqual(parse("outcutshare://follow?mode=off"), .follow(.off))
        XCTAssertEqual(parse("outcutshare://follow?mode=activeWindow"), .follow(.activeWindow))
        XCTAssertEqual(parse("outcutshare://follow?mode=CURSOR"), .follow(.cursor))
        XCTAssertNil(parse("outcutshare://follow?mode=nope"))
        XCTAssertNil(parse("outcutshare://follow"))
    }

    func testShareModes() {
        XCTAssertEqual(parse("outcutshare://share-mode?mode=virtualDisplay"),
                       .shareMode(.virtualDisplay))
        XCTAssertEqual(parse("outcutshare://share-mode?mode=hiddenwindow"),
                       .shareMode(.hiddenWindow))
        XCTAssertEqual(parse("outcutshare://share-mode?mode=virtualMonitor"),
                       .shareMode(.virtualMonitor))
        XCTAssertNil(parse("outcutshare://share-mode?mode=fullscreen"))
    }

    func testToggleOptions() {
        XCTAssertEqual(parse("outcutshare://toggle?option=preview"), .toggle(.preview))
        XCTAssertEqual(parse("outcutshare://toggle?option=hotbar"), .toggle(.hotbar))
        XCTAssertEqual(parse("outcutshare://toggle?option=cursorhighlights"),
                       .toggle(.cursorHighlights))
        XCTAssertEqual(parse("outcutshare://toggle?option=dimming"), .toggle(.dimming))
        XCTAssertNil(parse("outcutshare://toggle?option=styles"))
        XCTAssertNil(parse("outcutshare://toggle"))
    }

    func testDimPercent() {
        XCTAssertEqual(parse("outcutshare://dim?percent=45"), .dim(percent: 45))
        XCTAssertEqual(parse("outcutshare://dim?percent=0"), .dim(percent: 0))
        XCTAssertEqual(parse("outcutshare://dim?percent=100"), .dim(percent: 100))
        XCTAssertEqual(parse("outcutshare://dim?percent=42.5"), .dim(percent: 42.5))
        XCTAssertEqual(parse("outcutshare://DIM?Percent=45"), .dim(percent: 45))
    }

    func testDimRejectsMissingAndInvalidPercent() {
        XCTAssertNil(parse("outcutshare://dim"))
        XCTAssertNil(parse("outcutshare://dim?percent="))
        XCTAssertNil(parse("outcutshare://dim?percent=high"))
        XCTAssertNil(parse("outcutshare://dim?percent=-5"))
        XCTAssertNil(parse("outcutshare://dim?percent=101"))
    }

    func testRejectsUnknownCommandAndForeignScheme() {
        XCTAssertNil(parse("outcutshare://quit"))
        XCTAssertNil(parse("https://select"))
    }

    // MARK: matchPreset

    private let presets = [
        RegionPreset(id: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!,
                     name: "Left Half",
                     region: StoredRegion(rect: CGRect(x: 0, y: 0, width: 800, height: 600),
                                          displayID: 1),
                     shareModeRaw: "hiddenWindow"),
        RegionPreset(id: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000002")!,
                     name: "left half",
                     region: StoredRegion(rect: CGRect(x: 0, y: 0, width: 400, height: 300),
                                          displayID: 1),
                     shareModeRaw: "hiddenWindow"),
    ]

    func testMatchPresetByIdWinsOverName() {
        let match = URLCommand.matchPreset(
            id: "aaaaaaaa-0000-0000-0000-000000000002", name: "Left Half", in: presets)
        XCTAssertEqual(match?.name, "left half")
    }

    func testMatchPresetExactNameBeatsCaseInsensitive() {
        XCTAssertEqual(URLCommand.matchPreset(id: nil, name: "left half", in: presets)?.id,
                       presets[1].id)
    }

    func testMatchPresetFallsBackCaseInsensitively() {
        XCTAssertEqual(URLCommand.matchPreset(id: nil, name: "LEFT HALF", in: presets)?.id,
                       presets[0].id)
    }

    func testMatchPresetNoMatchReturnsNil() {
        XCTAssertNil(URLCommand.matchPreset(id: "nope", name: nil, in: presets))
        XCTAssertNil(URLCommand.matchPreset(id: nil, name: nil, in: presets))
    }
}
