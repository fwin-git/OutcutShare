# Localization

Outcut Share ships every user-facing feature in all supported languages.
English is the development language and fallback, but an English value alone
does not make a feature complete.

## Supported languages

| Locale | Language |
| --- | --- |
| `en` | English |
| `de` | German |
| `fr` | French |
| `es` | Spanish |
| `zh-Hans` | Simplified Chinese |
| `ja` | Japanese |
| `pt-BR` | Brazilian Portuguese |
| `ko` | Korean |
| `zh-Hant` | Traditional Chinese |
| `it` | Italian |

Locale identifiers are part of the bundle contract. Keep the exact identifiers:
`pt-BR` is Brazilian Portuguese, while `zh-Hans` and `zh-Hant` are distinct
script localizations. Do not replace them with broader or region-specific
identifiers without intentionally adding a new supported locale.

## How localized copy reaches the app

The source of truth is split between the typed Swift key list and two Apple
String Catalogs:

```text
L10n.Key ──> L10n.string(...) ──> Localizable.strings in the selected .lproj
                                      ▲
Localizable.xcstrings ── xcstringstool compile ──┘

InfoPlist.xcstrings ── xcstringstool compile ──> localized InfoPlist.strings
```

- `Sources/OutcutShare/L10n.swift` defines every application string key.
  Callers use `L10n.string(_:arguments:)`; they do not embed visible copy in
  Swift.
- `Resources/Localization/Localizable.xcstrings` contains the application
  copy. It currently has 257 keys, each finalized for all ten locales.
- `Resources/Localization/InfoPlist.xcstrings` contains system-facing bundle
  copy. It currently owns `NSMicrophoneUsageDescription`.
- `Support/Info.plist` declares English as the development language and lists
  the exact supported locale set in `CFBundleLocalizations`.
- `Makefile` compiles both catalogs into
  `Contents/Resources/<locale>.lproj/*.strings`.

At runtime, `L10n.string` resolves the selected localization bundle and loads
the key from `Localizable.strings`. The optional `localeIdentifier` argument is
for deterministic tests and debug probes. If that exact localization is not in
the bundle, resolution falls back to the English development localization.

## Adding or changing user-facing copy

Every feature change that adds or changes visible copy must update every
supported locale in the same commit:

1. Add a semantic case to `L10n.Key`. The raw value is a stable,
   dot-separated catalog key such as `settings.general.shareAs`.
2. Add the matching entry to `Localizable.xcstrings`. Include a useful comment
   when a translator needs UI, state, or audience context.
3. Add non-empty `stringUnit` values with `"state": "translated"` for all ten
   supported locales.
4. Use `L10n.string(.key)` at the call site. Pass dynamic values through
   `arguments:` instead of interpolating localized fragments.
5. Run the localization gates and inspect the affected UI in languages likely
   to change its width or line wrapping.

For macOS permission text or another value read from `Info.plist`, put the
translations in `InfoPlist.xcstrings` instead. Do not duplicate that copy in
`Localizable.xcstrings`.

Do not assemble sentences from separately translated fragments. Word order,
plural behavior, and punctuation differ between languages; give translators a
complete format string wherever possible.

## Placeholders and terminology

Translations must preserve the complete printf-style placeholder signature of
the English source, including type and positional markers. For example, a value
containing `%@` and `%d` must contain those same placeholders after
translation. `LocalizationCatalogTests` enforces this contract.

Keep an identity unchanged when translating it would break recognition or
behavior:

- product and third-party names such as Outcut Share, Finder, Zoom, and Teams;
- keyboard glyphs and shortcuts;
- filenames, extensions, bundle identifiers, URL schemes, and protocol values;
- technical units such as `fps`, pixel dimensions, and format names.

Translate surrounding prose naturally. Do not copy an English sentence into
another locale merely to satisfy catalog completeness. Use neutral Traditional
Chinese for `zh-Hant`; do not assume Taiwan-specific terminology unless that
locale is deliberately split in the future.

## Adding another language

Adding a locale is a repository-wide contract change. Update all of these
together:

1. Add finalized values to every entry in `Localizable.xcstrings` and
   `InfoPlist.xcstrings`.
2. Add the exact identifier to `CFBundleLocalizations` in
   `Support/Info.plist`.
3. Add it to `supportedLocales` in
   `Tests/OutcutShareTests/LocalizationCatalogTests.swift`.
4. Add it, plus the expected `menu.selectRegion` translation, to the parallel
   `locales` and `expected` arrays in `Scripts/verify-localizations.sh`.
5. Build the app, confirm both compiled string tables exist, and visually
   inspect representative compact and text-heavy windows.

No runtime switch statement is needed: `L10n` resolves any exact locale that
the bundle contains.

## Verification

Run the static source and catalog checks first:

```sh
Scripts/check-localization-source.sh
jq empty Resources/Localization/Localizable.xcstrings \
  Resources/Localization/InfoPlist.xcstrings
swift test --filter LocalizationCatalogTests
```

`Scripts/check-localization-source.sh` catches common visible string literals
in production Swift. Demo fixtures are excluded because they render controlled
showcase content, not application UI; do not use that exclusion for a product
feature.

The catalog tests enforce:

- the exact ten-locale set on every application and Info.plist entry;
- translated, non-empty values;
- placeholder preservation;
- agreement with `CFBundleLocalizations`;
- successful `xcstringstool` compilation of both tables for every locale.

Before merging a feature, run the complete suite and verify the packaged app:

```sh
swift test
make -B app
Scripts/verify-localizations.sh build/OutcutShare.app
find build/OutcutShare.app/Contents/Resources \
  -type f \( -name Localizable.strings -o -name InfoPlist.strings \) \
  | sort
```

The packaged verifier launches the executable once per locale through
`--localization-test=<locale>` and checks a representative runtime value.
There must be two compiled tables for each supported locale.

Automated checks cannot catch clipped labels or awkward wrapping. For a feature
with new UI copy, launch the affected window under each changed locale and
inspect it at its normal size. At minimum, cover the longest likely labels and
compact windows; when adding a language, inspect representative settings panes
for that language before merging.
