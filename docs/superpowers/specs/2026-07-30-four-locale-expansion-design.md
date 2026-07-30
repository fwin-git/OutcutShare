# Four-Locale Expansion Design

## Goal

Expand Outcut Share's complete localization contract from six to ten locales
by adding Brazilian Portuguese (`pt-BR`), Korean (`ko`), Traditional Chinese
(`zh-Hant`), and Italian (`it`).

## Locale Model

The four additions are exact Apple locale identifiers:

- `pt-BR`, not generic `pt`, because the requested translation is Brazilian
  Portuguese and its terminology differs from European Portuguese.
- `ko` for Korean.
- `zh-Hant`, not `zh-TW`, so the Traditional Chinese script localization is
  available wherever macOS selects that script. Wording should be neutral
  Traditional Chinese suitable for Taiwan and Hong Kong where possible.
- `it` for Italian.

English remains the development language and fallback. Existing German,
French, Spanish, Simplified Chinese, and Japanese values remain unchanged.

## Catalog Content

Every one of the 257 keys in
`Resources/Localization/Localizable.xcstrings` receives a finalized,
non-empty translation in all four locales. The microphone permission
description in `InfoPlist.xcstrings` receives the same treatment.

Brand names, keyboard glyphs, file extensions, protocol values, and technical
units remain unchanged where translation would alter their identity.
Placeholders such as `%@`, `%d`, and positional variants must retain exactly
the English signature. UI terminology should remain consistent within each
locale, especially for sharing, recording, presets, virtual displays,
permissions, pause/resume, and follow modes.

The catalogs remain the only source of translated runtime copy. No runtime
machine translation, locale-specific source branches, or duplicated string
tables are introduced.

## Bundle and Packaging Contract

`Support/Info.plist` declares all ten locales in `CFBundleLocalizations`.
`Scripts/verify-localizations.sh` requires both `Localizable.strings` and
`InfoPlist.strings` for every locale and probes one representative localized
menu value from the packaged executable.

The catalog compiler test continues to verify the real `xcstringstool` output,
so a locale is not considered supported unless both runtime tables are
actually generated.

## Test-First Rollout

The supported-locale contract is expanded in tests before either catalog is
changed. This must fail against the six-locale catalogs and declarations,
proving the test detects the missing feature.

After translation:

- every catalog entry has exactly the ten supported locales;
- every string unit is finalized and non-empty;
- every translation preserves its placeholder signature;
- `Info.plist` declares exactly the catalog locale set;
- catalog compilation produces 20 runtime `.strings` files;
- the packaged executable returns the expected representative value for all
  ten locales.

## Runtime QA

Build and sign the application through the existing `make app` path. Launch an
isolated copy under each new locale and capture the General and Permissions
settings panes. Inspect all eight screenshots for:

- correct locale selection rather than English fallback;
- all eight toolbar tabs remaining visible;
- clipping, truncation, overlap, or malformed placeholders;
- untranslated user-facing English copy;
- appropriate line wrapping for Korean and Traditional Chinese.

The existing six locales receive automated regression coverage unchanged.

## Scope

This milestone changes application and bundle translations only. It does not
add European Portuguese, App Store listing metadata, localized screenshots
for distribution, or unrelated UI behavior.
