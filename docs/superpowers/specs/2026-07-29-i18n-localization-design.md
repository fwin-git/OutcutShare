# Outcut Share Internationalization Design

## Goal

Internationalize the macOS app and ship complete English, German, French,
Spanish, Simplified Chinese, and Japanese localizations. The locale identifiers
are `en`, `de`, `fr`, `es`, `zh-Hans`, and `ja`; “CH” and “JP” in the original
request are interpreted as Chinese and Japanese.

Outcut Share follows macOS language selection. The system language or the
language chosen for Outcut Share in System Settings takes effect at the next
launch. The app does not add a separate language preference.

## Scope

Localize all production-facing text in the macOS app:

- menu-bar commands and dynamically changing menu titles;
- every settings page, section, field, caption, tab, and validation message;
- onboarding, permission status, alerts, and error presentation;
- region-selection and resize overlays;
- the floating hotbar, preview, and virtual-monitor controls;
- capture-result, OCR, recording-trim, and recent-capture interfaces;
- viewer-facing defaults such as the privacy-pause message;
- tooltips and accessibility labels; and
- the microphone privacy description from the app's Info.plist.

The following values must remain stable and untranslated:

- URL-scheme commands, query values, and Raycast protocol values;
- `UserDefaults` keys and stored enum raw values;
- bundle identifiers, system symbols, file extensions, and debug flags;
- user-created preset names and paths;
- capture filenames and date-format components; and
- debug-only CLI logs and feature-showcase harness content.

The Raycast extension, repository documentation, and demo choreography are
separate artifacts and are not localized in this change.

## Architecture

### String catalogs

Use two Apple String Catalogs:

- `Resources/Localization/Localizable.xcstrings` for application text; and
- `Resources/Localization/InfoPlist.xcstrings` for privacy descriptions.

English is the source language and complete fallback. Every application key has
translations for all six supported locales. Keys are stable semantic identifiers
grouped by surface, for example `menu.selectRegion`, `settings.general.sharing`,
and `capture.delete.confirmation`.

The catalog owns complete sentences. Code does not concatenate translated
fragments. Dynamic content uses catalog substitutions so translators can reorder
values. Values such as dimensions, durations, percentages, and counts use
Foundation formatting appropriate to the active locale where that does not alter
a protocol or filename.

### Typed access

Add a focused `L10n.swift` facade. It exposes named static properties and methods
for application strings, including methods for messages with substitutions. Both
SwiftUI and AppKit receive resolved `String` values from this facade. This avoids
a split where SwiftUI localizes implicit literals but AppKit bypasses the catalog.

The facade resolves against `Bundle.main` in production and supports explicit
bundle and locale injection for tests. English values are present in the catalog,
not duplicated as a second translation store in Swift.

Display-name properties on domain enums, such as follow modes and hotkey actions,
become localized computed properties. Their raw values and persistence behavior
do not change.

### Bundle integration

`make app` compiles both catalogs with Apple's `xcstringstool` and installs the
resulting `.lproj` resources in `OutcutShare.app/Contents/Resources`. The catalog
files are explicit Makefile dependencies so translation changes rebuild the app.

`Support/Info.plist` advertises `en`, `de`, `fr`, `es`, `zh-Hans`, and `ja` via
`CFBundleLocalizations` while retaining `en` as `CFBundleDevelopmentRegion`.
Localized `InfoPlist.strings` files override the microphone privacy description.

The ordinary Swift package continues to compile without requiring resources at
runtime. The release-style app assembly is authoritative for localization bundle
verification because it is the artifact users launch.

## Data Flow and Behavior

At launch, Foundation selects the best localization from the app bundle using
macOS language preferences. UI construction asks `L10n` for each visible string.
Dynamic state changes select another localized key, such as Pause versus Resume,
without changing state-machine behavior.

If macOS requests an unsupported locale, Foundation falls back to English. The
build and test gates prevent missing supported-locale translations. A truly
unknown key remains visibly identifiable during development and fails catalog
coverage tests rather than being silently accepted as a valid translation.

User-authored values pass through unchanged. Existing saved preferences keep
their raw representations. Defaults that are genuinely user-facing are resolved
from localization only when no user value exists; this avoids overwriting an
existing customized title or pause message.

AppKit alerts may combine a localized app explanation with
`error.localizedDescription`. System-provided descriptions remain the operating
system's responsibility, while Outcut Share's own error cases use localized
descriptions.

## Translation Quality

Translations should sound native and concise rather than mirror English word
order. Product names, meeting-app names, macOS control names, keyboard glyphs,
and technical terms are retained where users see those names in the operating
system.

German uses natural menu and settings terminology suitable for the user's German
macOS environment. French and Spanish use neutral standard variants. Chinese is
Simplified Chinese (`zh-Hans`). Japanese uses normal Japanese UI conventions.

The same action uses consistent terminology across the menu bar, hotbar,
settings, permissions, and alerts. Text length is checked in the actual app,
especially for German and French, without shrinking fonts or truncating core
instructions.

## Testing

Implementation follows test-driven development:

1. Add failing catalog-structure tests before the catalogs and access layer.
2. Add failing tests for locale lookup, fallback, substitutions, and stable enum
   raw values before implementing `L10n`.
3. Migrate one UI surface at a time, keeping the suite green and extending
   coverage where dynamic labels are testable.

Automated gates prove:

- the exact supported locale set is present;
- every key has a non-empty, finalized value in all six locales;
- placeholder signatures match across translations;
- Info.plist declares the same locale set;
- the microphone privacy description exists in every locale;
- localized enum display names do not alter raw values;
- the catalogs compile successfully with `xcstringstool`;
- the built app contains all six `.lproj` directories;
- representative runtime lookups return the expected locale rather than English;
- the existing Swift suite remains green; and
- the release build produces no warnings.

A source audit identifies remaining production UI string literals. Deliberate
nonlocalized technical strings are narrowly allowlisted with a reason; broad
file-level exclusions are not used. Debug harness and demo files are excluded
explicitly according to the scope above.

## Runtime Verification

Build the signed app with `make app`, then launch the existing settings,
permissions, selector, result-card, and sharing debug surfaces under each
supported language. At minimum, capture and inspect English, German, French,
Spanish, Simplified Chinese, and Japanese settings/permission windows. Exercise
dynamic menu and hotbar states in more than one non-English locale.

Verification checks readable layout, correct substitutions, localized
accessibility/help text, and English fallback under an unsupported locale. It
must not modify the user's saved settings permanently; any temporary language or
defaults overrides are restored after testing.

## Delivery

All work stays on `feature/i18n-localization` in the linked worktree created from
`main`. The feature is complete only when the catalogs, source migration,
localized Info.plist content, automated coverage gates, release app resources,
and runtime locale checks all pass. This task does not cut a release or merge to
`main`.
