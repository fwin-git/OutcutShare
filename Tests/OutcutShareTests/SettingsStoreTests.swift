import XCTest
import AppKit
@testable import OutcutShare

final class SettingsStoreTests: XCTestCase {
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

    func testDefaults() {
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.dimOpacity, 0.6, accuracy: 0.0001)
        XCTAssertTrue(store.dimmingEnabled)
        XCTAssertTrue(store.showRegionBorder)
        XCTAssertEqual(store.frameRate, 30)
    }

    func testPersistenceAcrossInstances() {
        let store = SettingsStore(defaults: defaults)
        store.dimOpacity = 0.35
        store.dimmingEnabled = false
        store.showRegionBorder = false
        store.frameRate = 60

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.dimOpacity, 0.35, accuracy: 0.0001)
        XCTAssertFalse(reloaded.dimmingEnabled)
        XCTAssertFalse(reloaded.showRegionBorder)
        XCTAssertEqual(reloaded.frameRate, 60)
    }

    func testFollowTargetDefaultsToActiveWindow() {
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.followTarget, .activeWindow)
    }

    func testFollowTargetPersistsAcrossInstances() {
        let store = SettingsStore(defaults: defaults)
        store.followTarget = .cursor
        XCTAssertEqual(SettingsStore(defaults: defaults).followTarget, .cursor)
    }

    func testFollowTargetIgnoresStoredOff() {
        defaults.set("off", forKey: "followTarget")
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.followTarget, .activeWindow)
    }

    func testPauseScreenDefaultsAndPersistence() {
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.pauseMessage, "")
        XCTAssertEqual(store.pauseImagePath, "")
        store.pauseMessage = "Be right back"
        store.pauseImagePath = "/tmp/logo.png"
        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.pauseMessage, "Be right back")
        XCTAssertEqual(reloaded.pauseImagePath, "/tmp/logo.png")
    }

    @MainActor
    func testPauseScreenContentResolution() {
        var defaultMessageRequests = 0
        let localizedDefault = {
            defaultMessageRequests += 1
            return "Die Freigabe ist pausiert"
        }
        let stock = PauseScreenContent.resolve(
            message: "",
            imagePath: "",
            defaultMessage: localizedDefault
        )
        XCTAssertEqual(stock.text, "Die Freigabe ist pausiert")
        XCTAssertNil(stock.image)
        XCTAssertEqual(defaultMessageRequests, 1)

        XCTAssertEqual(
            PauseScreenContent.resolve(
                message: " brb ☕️ ",
                imagePath: "",
                defaultMessage: localizedDefault
            ).text,
            "brb ☕️"
        )
        XCTAssertEqual(defaultMessageRequests, 1)
        // An image path that can't be loaded falls back to the text screen.
        let broken = PauseScreenContent.resolve(message: "hi", imagePath: "/nope/missing.png")
        XCTAssertNil(broken.image)
        XCTAssertEqual(broken.text, "hi")
    }

    func testRecordingAudioDefaultsAndPersistence() {
        let store = SettingsStore(defaults: defaults)
        XCTAssertTrue(store.recordSystemAudio)
        XCTAssertFalse(store.recordMicrophone)
        store.recordSystemAudio = false
        store.recordMicrophone = true
        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertFalse(reloaded.recordSystemAudio)
        XCTAssertTrue(reloaded.recordMicrophone)
    }

    func testZoomFactorDefaultAndPersistence() {
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.zoomFactor, 2.0, accuracy: 0.0001)
        store.zoomFactor = 3.0
        XCTAssertEqual(SettingsStore(defaults: defaults).zoomFactor, 3.0, accuracy: 0.0001)
    }

    func testScreenshotDefaults() {
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.screenshotFolder, "")
        XCTAssertTrue(store.screenshotFolderURL.path.hasSuffix("Pictures/OutcutShare"))
        XCTAssertEqual(store.screenshotMaxSize, 0)
        XCTAssertEqual(store.screenshotQuality, 1.0, accuracy: 0.0001)
        XCTAssertFalse(store.screenshotShadow)
    }

    func testScreenshotSettingsPersistAcrossInstances() {
        let store = SettingsStore(defaults: defaults)
        store.screenshotFolder = "/tmp/shots"
        store.screenshotMaxSize = 2048
        store.screenshotQuality = 0.8
        store.screenshotShadow = true

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.screenshotFolder, "/tmp/shots")
        XCTAssertEqual(reloaded.screenshotFolderURL.path, "/tmp/shots")
        XCTAssertEqual(reloaded.screenshotMaxSize, 2048)
        XCTAssertEqual(reloaded.screenshotQuality, 0.8, accuracy: 0.0001)
        XCTAssertTrue(reloaded.screenshotShadow)
    }

    func testPrivacyDefaultsAndPersistence() {
        let store = SettingsStore(defaults: defaults)
        XCTAssertTrue(store.hideNotificationBanners)
        XCTAssertTrue(store.hiddenApps.isEmpty)

        store.hideNotificationBanners = false
        store.hiddenApps = [HiddenApp(bundleID: "com.apple.mail", name: "Mail"),
                            HiddenApp(bundleID: "com.apple.MobileSMS", name: "Messages")]

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertFalse(reloaded.hideNotificationBanners)
        XCTAssertEqual(reloaded.hiddenApps.map(\.bundleID),
                       ["com.apple.mail", "com.apple.MobileSMS"])
        XCTAssertEqual(reloaded.hiddenApps.map(\.name), ["Mail", "Messages"])
    }

    func testExcludedBundleIDsComposition() {
        let store = SettingsStore(defaults: defaults)
        store.hiddenApps = [HiddenApp(bundleID: "com.apple.mail", name: "Mail")]
        XCTAssertEqual(store.excludedBundleIDs,
                       ["com.apple.mail", "com.apple.notificationcenterui"])
        store.hideNotificationBanners = false
        XCTAssertEqual(store.excludedBundleIDs, ["com.apple.mail"])
    }

    func testDockIconSettingDefaultsOffAndPersists() {
        let store = SettingsStore(defaults: defaults)
        XCTAssertFalse(store.dockIconWhileActive)
        store.dockIconWhileActive = true
        XCTAssertTrue(SettingsStore(defaults: defaults).dockIconWhileActive)
    }

    func testCrispOutputDefaultsOffAndPersists() {
        let store = SettingsStore(defaults: defaults)
        XCTAssertFalse(store.crispOutput)
        store.crispOutput = true
        XCTAssertTrue(SettingsStore(defaults: defaults).crispOutput)
    }

    func testPauseStyleDefaultsToPrivacyScreenAndPersists() {
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.pauseStyle, .privacyScreen)
        store.pauseStyle = .freeze
        XCTAssertEqual(SettingsStore(defaults: defaults).pauseStyle, .freeze)
    }

    func testShareModeDefaultsToVirtualDisplay() {
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.shareMode, .virtualDisplay)
    }

    func testShareModePersists() {
        let store = SettingsStore(defaults: defaults)
        store.shareMode = .hiddenWindow
        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.shareMode, .hiddenWindow)
    }

    func testDimOpacityClamped() {
        let store = SettingsStore(defaults: defaults)
        store.dimOpacity = 1.5
        XCTAssertEqual(store.dimOpacity, 0.9, accuracy: 0.0001)
        store.dimOpacity = -0.2
        XCTAssertEqual(store.dimOpacity, 0.0, accuracy: 0.0001)
    }

    func testBorderDefaults() {
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.borderStyle, .dashed)
        XCTAssertEqual(store.borderRadius, 8, accuracy: 0.0001)
        XCTAssertEqual(store.borderThickness, 3, accuracy: 0.0001)
        XCTAssertEqual(store.borderColor.hexRGBA, "#FF3B30FF")
    }

    func testBorderSettingsPersist() {
        let store = SettingsStore(defaults: defaults)
        store.borderStyle = .dotted
        store.borderRadius = 14
        store.borderThickness = 6
        store.borderColor = NSColor(hexRGBA: "#00FF00FF")!

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.borderStyle, .dotted)
        XCTAssertEqual(reloaded.borderRadius, 14, accuracy: 0.0001)
        XCTAssertEqual(reloaded.borderThickness, 6, accuracy: 0.0001)
        XCTAssertEqual(reloaded.borderColor.hexRGBA, "#00FF00FF")
    }

    func testBorderRadiusAndThicknessClamped() {
        let store = SettingsStore(defaults: defaults)
        store.borderRadius = -5
        XCTAssertEqual(store.borderRadius, 0, accuracy: 0.0001)
        store.borderRadius = 100
        XCTAssertEqual(store.borderRadius, 30, accuracy: 0.0001)
        store.borderThickness = 0
        XCTAssertEqual(store.borderThickness, 1, accuracy: 0.0001)
        store.borderThickness = 50
        XCTAssertEqual(store.borderThickness, 10, accuracy: 0.0001)
    }

    func testHotbarScaleDefaultAndPersistence() {
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.hotbarScale, 1.0, accuracy: 0.0001)
        store.hotbarScale = 1.5
        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.hotbarScale, 1.5, accuracy: 0.0001)
    }

    func testHotbarScaleClamped() {
        let store = SettingsStore(defaults: defaults)
        store.hotbarScale = 0.5
        XCTAssertEqual(store.hotbarScale, 1.0, accuracy: 0.0001)
        store.hotbarScale = 3.0
        XCTAssertEqual(store.hotbarScale, 2.0, accuracy: 0.0001)
    }

    func testAppLanguageDefaultsToSystem() {
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.appLanguage, "")
    }

    func testAppLanguageWritesAndClearsAppleLanguagesOverride() {
        let store = SettingsStore(defaults: defaults)
        store.appLanguage = "ja"
        XCTAssertEqual(
            defaults.persistentDomain(forName: suiteName)?["AppleLanguages"] as? [String],
            ["ja"]
        )
        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.appLanguage, "ja")
        reloaded.appLanguage = ""
        XCTAssertNil(defaults.persistentDomain(forName: suiteName)?["AppleLanguages"])
    }

    func testHexColorRoundTrip() {
        let color = NSColor(hexRGBA: "#3366CC80")
        XCTAssertNotNil(color)
        XCTAssertEqual(color?.hexRGBA, "#3366CC80")
        XCTAssertNil(NSColor(hexRGBA: "not-a-color"))
        XCTAssertNil(NSColor(hexRGBA: "#12345"))
    }

    func testChangePostsNotification() {
        let store = SettingsStore(defaults: defaults)
        let expectation = expectation(forNotification: settingsChangedNotification,
                                      object: nil)
        store.dimOpacity = 0.5
        wait(for: [expectation], timeout: 1.0)
    }
}
