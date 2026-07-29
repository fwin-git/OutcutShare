import Foundation

enum L10n {
    enum Key: String {
        case menuSelectRegion = "menu.selectRegion"
        case presetDefaultName = "preset.defaultName"
    }

    static func string(
        _ key: Key,
        bundle: Bundle = .main,
        localeIdentifier: String? = nil,
        arguments: [CVarArg] = []
    ) -> String {
        let resolvedBundle = localizedBundle(
            in: bundle,
            localeIdentifier: localeIdentifier
        )
        let format = resolvedBundle.localizedString(
            forKey: key.rawValue,
            value: nil,
            table: "Localizable"
        )
        guard !arguments.isEmpty else { return format }
        let locale = localeIdentifier.map(Locale.init(identifier:)) ?? .current
        return String(format: format, locale: locale, arguments: arguments)
    }

    static func localizedBundle(
        in bundle: Bundle,
        localeIdentifier: String?
    ) -> Bundle {
        guard let localeIdentifier else { return bundle }
        if let localized = localizationBundle(
            in: bundle,
            localeIdentifier: localeIdentifier
        ) {
            return localized
        }
        let fallback = bundle.developmentLocalization ?? "en"
        return localizationBundle(in: bundle, localeIdentifier: fallback) ?? bundle
    }

    private static func localizationBundle(
        in bundle: Bundle,
        localeIdentifier: String
    ) -> Bundle? {
        guard let path = bundle.path(
            forResource: localeIdentifier,
            ofType: "lproj"
        ) else {
            return nil
        }
        return Bundle(path: path)
    }
}
