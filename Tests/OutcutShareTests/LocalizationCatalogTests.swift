import Foundation
import XCTest

final class LocalizationCatalogTests: XCTestCase {
    private struct Catalog: Decodable {
        let sourceLanguage: String
        let strings: [String: Entry]
    }

    private struct Entry: Decodable {
        let localizations: [String: Localization]
    }

    private struct Localization: Decodable {
        let stringUnit: StringUnit
    }

    private struct StringUnit: Decodable {
        let state: String
        let value: String
    }

    private let supportedLocales = Set(["en", "de", "fr", "es", "zh-Hans", "ja"])

    func testEveryAppStringIsFinalizedForEverySupportedLocale() throws {
        let catalog = try loadCatalog(named: "Localizable")

        XCTAssertEqual(catalog.sourceLanguage, "en")
        XCTAssertFalse(catalog.strings.isEmpty)
        for (key, entry) in catalog.strings {
            XCTAssertEqual(Set(entry.localizations.keys), supportedLocales, key)
            for locale in supportedLocales {
                let unit = try XCTUnwrap(entry.localizations[locale]?.stringUnit,
                                         "\(key) [\(locale)]")
                XCTAssertEqual(unit.state, "translated", "\(key) [\(locale)]")
                XCTAssertFalse(
                    unit.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    "\(key) [\(locale)]"
                )
            }
        }
    }

    func testEveryInfoPlistStringIsFinalizedForEverySupportedLocale() throws {
        let catalog = try loadCatalog(named: "InfoPlist")

        XCTAssertEqual(catalog.sourceLanguage, "en")
        XCTAssertEqual(Set(catalog.strings.keys), ["NSMicrophoneUsageDescription"])
        for (key, entry) in catalog.strings {
            XCTAssertEqual(Set(entry.localizations.keys), supportedLocales, key)
            for locale in supportedLocales {
                let unit = try XCTUnwrap(entry.localizations[locale]?.stringUnit,
                                         "\(key) [\(locale)]")
                XCTAssertEqual(unit.state, "translated", "\(key) [\(locale)]")
                XCTAssertFalse(
                    unit.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    "\(key) [\(locale)]"
                )
            }
        }
    }

    func testTranslationsPreserveFormatPlaceholderSignatures() throws {
        for catalogName in ["Localizable", "InfoPlist"] {
            let catalog = try loadCatalog(named: catalogName)
            for (key, entry) in catalog.strings {
                let english = try XCTUnwrap(entry.localizations["en"]?.stringUnit.value)
                let expected = placeholderSignature(in: english)
                for locale in supportedLocales.subtracting(["en"]) {
                    let translation = try XCTUnwrap(
                        entry.localizations[locale]?.stringUnit.value
                    )
                    XCTAssertEqual(
                        placeholderSignature(in: translation),
                        expected,
                        "\(catalogName).xcstrings: \(key) [\(locale)]"
                    )
                }
            }
        }
    }

    func testInfoPlistDeclaresTheCatalogLocaleSet() throws {
        let data = try Data(contentsOf: repositoryRoot.appendingPathComponent(
            "Support/Info.plist"
        ))
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: Any]
        )

        XCTAssertEqual(plist["CFBundleDevelopmentRegion"] as? String, "en")
        XCTAssertEqual(
            Set(try XCTUnwrap(plist["CFBundleLocalizations"] as? [String])),
            supportedLocales
        )
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func loadCatalog(named name: String) throws -> Catalog {
        let url = repositoryRoot
            .appendingPathComponent("Resources/Localization")
            .appendingPathComponent("\(name).xcstrings")
        return try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
    }

    private func placeholderSignature(in value: String) -> [String] {
        let pattern = #"%(?:\d+\$)?[-+ 0#]*\d*(?:\.\d+)?(?:hh|h|ll|l|q|z|t|j)?[@a-zA-Z%]"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(value.startIndex..., in: value)
        return regex.matches(in: value, range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: value) else { return nil }
            let token = String(value[swiftRange])
                .replacingOccurrences(
                    of: #"%\d+\$"#,
                    with: "%",
                    options: .regularExpression
                )
            return token == "%%" ? nil : token
        }
    }
}
