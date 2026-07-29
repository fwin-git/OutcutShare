import Foundation
import XCTest
@testable import OutcutShare

final class LocalizationTests: XCTestCase {
    private var fixtureRoot: URL!
    private var fixtureBundle: Bundle!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OutcutShareLocalization-\(UUID().uuidString)")
        let bundleURL = fixtureRoot.appendingPathComponent("Fixture.bundle")
        let resources = bundleURL.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(
            at: resources.appendingPathComponent("en.lproj"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: resources.appendingPathComponent("de.lproj"),
            withIntermediateDirectories: true
        )

        let info: [String: Any] = [
            "CFBundleIdentifier": "com.outcutshare.tests.localization.\(UUID().uuidString)",
            "CFBundlePackageType": "BNDL",
            "CFBundleDevelopmentRegion": "en",
            "CFBundleLocalizations": ["en", "de"],
        ]
        let infoData = try PropertyListSerialization.data(
            fromPropertyList: info,
            format: .xml,
            options: 0
        )
        try infoData.write(to: bundleURL.appendingPathComponent("Contents/Info.plist"))

        try writeStrings(
            [
                "menu.selectRegion": "Select Region & Share",
                "preset.defaultName": "Preset %d",
                "settings.general.shareWindowDefaultTitle":
                    "Outcut Share (Share Region)",
            ],
            locale: "en",
            resources: resources
        )
        try writeStrings(
            [
                "menu.selectRegion": "Bereich auswählen und teilen",
                "preset.defaultName": "Voreinstellung %d",
                "settings.general.shareWindowDefaultTitle":
                    "Outcut Share (Bereich teilen)",
            ],
            locale: "de",
            resources: resources
        )
        fixtureBundle = try XCTUnwrap(Bundle(url: bundleURL))
    }

    override func tearDownWithError() throws {
        if let fixtureRoot {
            try? FileManager.default.removeItem(at: fixtureRoot)
        }
        fixtureBundle = nil
        fixtureRoot = nil
        try super.tearDownWithError()
    }

    func testExplicitLocaleResolvesThatLocalization() {
        XCTAssertEqual(
            L10n.string(
                .menuSelectRegion,
                bundle: fixtureBundle,
                localeIdentifier: "de"
            ),
            "Bereich auswählen und teilen"
        )
    }

    func testUnsupportedLocaleFallsBackToEnglishDevelopmentLocalization() {
        XCTAssertEqual(
            L10n.string(
                .menuSelectRegion,
                bundle: fixtureBundle,
                localeIdentifier: "it"
            ),
            "Select Region & Share"
        )
    }

    func testArgumentsFormatTheSelectedTranslation() {
        XCTAssertEqual(
            L10n.string(
                .presetDefaultName,
                bundle: fixtureBundle,
                localeIdentifier: "de",
                arguments: [3]
            ),
            "Voreinstellung 3"
        )
    }

    func testViewerFacingDefaultResolvesInTheRequestedLocale() {
        XCTAssertEqual(
            L10n.string(
                .settingsGeneralShareWindowDefaultTitle,
                bundle: fixtureBundle,
                localeIdentifier: "de"
            ),
            "Outcut Share (Bereich teilen)"
        )
    }

    private func writeStrings(
        _ strings: [String: String],
        locale: String,
        resources: URL
    ) throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: strings,
            format: .xml,
            options: 0
        )
        try data.write(
            to: resources
                .appendingPathComponent("\(locale).lproj")
                .appendingPathComponent("Localizable.strings")
        )
    }
}
