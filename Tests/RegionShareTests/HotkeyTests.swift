import XCTest
import AppKit
import Carbon.HIToolbox
@testable import RegionShare

final class HotkeyTests: XCTestCase {
    func testRawValueRoundTrip() {
        let combo = KeyCombo(keyCode: 1, modifiers: [.command, .shift])
        let restored = KeyCombo(rawValue: combo.rawValue)
        XCTAssertEqual(restored, combo)
        XCTAssertNil(KeyCombo(rawValue: "garbage"))
        XCTAssertNil(KeyCombo(rawValue: "1:2:3"))
    }

    func testModifiersAreMaskedToDeviceIndependent() {
        // Raw NSEvent flags carry device-dependent bits that must not leak
        // into persistence/equality.
        let raw = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.command.rawValue | 0x8)
        let combo = KeyCombo(keyCode: 1, modifiers: raw)
        XCTAssertEqual(combo, KeyCombo(keyCode: 1, modifiers: .command))
    }

    func testDisplayStringForSpecialKeys() {
        XCTAssertEqual(KeyCombo(keyCode: 96, modifiers: []).displayString, "F5")
        XCTAssertEqual(KeyCombo(keyCode: 49, modifiers: [.command]).displayString, "⌘Space")
        XCTAssertEqual(KeyCombo(keyCode: 36, modifiers: [.control, .option, .shift, .command]).displayString,
                       "⌃⌥⇧⌘↩")
    }

    func testCarbonModifierMapping() {
        let combo = KeyCombo(keyCode: 1, modifiers: [.command, .shift, .option, .control])
        XCTAssertEqual(combo.carbonModifiers, UInt32(cmdKey | shiftKey | optionKey | controlKey))
    }

    func testRiskyCombosAreBareNonFunctionKeys() {
        XCTAssertTrue(KeyCombo(keyCode: 1, modifiers: []).isRisky)          // bare letter
        XCTAssertFalse(KeyCombo(keyCode: 96, modifiers: []).isRisky)        // bare F5
        XCTAssertFalse(KeyCombo(keyCode: 1, modifiers: [.command]).isRisky) // has modifier
    }

    func testDuplicateDetection() {
        let combo = KeyCombo(keyCode: 1, modifiers: [.command])
        let other = KeyCombo(keyCode: 2, modifiers: [.command])
        let dupes = HotkeyAction.duplicates(in: [.selectRegion: combo,
                                                 .stopSharing: combo,
                                                 .adjustRegion: other])
        XCTAssertEqual(dupes, [combo])
        XCTAssertTrue(HotkeyAction.duplicates(in: [.selectRegion: combo,
                                                   .adjustRegion: other]).isEmpty)
    }

    func testEveryActionHasDistinctDefault() {
        let defaults = HotkeyAction.allCases.compactMap(\.defaultCombo)
        XCTAssertEqual(defaults.count, HotkeyAction.allCases.count)
        XCTAssertEqual(Set(defaults).count, defaults.count)
    }
}

final class HotkeySettingsTests: XCTestCase {
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

    func testHotkeysDefaultToActionDefaults() {
        let store = SettingsStore(defaults: defaults)
        for action in HotkeyAction.allCases {
            XCTAssertEqual(store.hotkey(for: action), action.defaultCombo)
        }
    }

    func testHotkeyPersistsAndClears() {
        let store = SettingsStore(defaults: defaults)
        let combo = KeyCombo(keyCode: 96, modifiers: [.option])
        store.setHotkey(combo, for: .selectRegion)
        store.setHotkey(nil, for: .stopSharing) // explicit clear must survive reload

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.hotkey(for: .selectRegion), combo)
        XCTAssertNil(reloaded.hotkey(for: .stopSharing))
        XCTAssertEqual(reloaded.hotkey(for: .adjustRegion), HotkeyAction.adjustRegion.defaultCombo)
    }

    func testSettingHotkeyPostsChangeNotification() {
        let store = SettingsStore(defaults: defaults)
        let expectation = expectation(forNotification: settingsChangedNotification, object: nil)
        store.setHotkey(KeyCombo(keyCode: 96, modifiers: [.option]), for: .selectRegion)
        wait(for: [expectation], timeout: 1.0)
    }
}
