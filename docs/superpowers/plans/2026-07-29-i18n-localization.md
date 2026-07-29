# Outcut Share Internationalization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the macOS app with complete English, German, French, Spanish, Simplified Chinese, and Japanese localization selected by macOS.

**Architecture:** Apple String Catalogs are the single translation store. A typed `L10n` facade resolves catalog keys for both AppKit and SwiftUI, while `make app` compiles the catalogs into the main app bundle and a source lint prevents production UI literals from bypassing localization.

**Tech Stack:** Swift 5 language mode, AppKit, SwiftUI, Foundation `Bundle`, XCTest, Apple `xcstringstool`, Make.

## Global Constraints

- Supported locale identifiers are exactly `en`, `de`, `fr`, `es`, `zh-Hans`, and `ja`.
- English is the development language and complete fallback.
- Language selection follows macOS system/per-app preferences; do not add an in-app picker.
- Localize all production UI, alerts, viewer-facing defaults, help, accessibility text, and the microphone privacy description.
- Do not translate URL protocol values, persisted raw values/keys, identifiers, filenames, debug CLI output, user-authored text, Raycast, docs, or demo choreography.
- Preserve Swift 5 language mode, macOS 14 minimum deployment, existing state behavior, and zero build warnings.
- Keep complete sentences in catalogs; use substitutions instead of concatenating translated fragments.
- Work only on `feature/i18n-localization`; do not merge, push, release, or modify `main`.

---

## File Map

**Create:**

- `Resources/Localization/Localizable.xcstrings` — source and five translated values for every app string.
- `Resources/Localization/InfoPlist.xcstrings` — localized microphone privacy description.
- `Sources/OutcutShare/L10n.swift` — typed keys and locale-aware catalog lookup.
- `Tests/OutcutShareTests/LocalizationCatalogTests.swift` — catalog schema, locale, value, placeholder, and Info.plist parity tests.
- `Tests/OutcutShareTests/LocalizationTests.swift` — `L10n` lookup, substitution, and fallback tests.
- `Scripts/check-localization-source.sh` — static lint for production UI literal bypasses.
- `Scripts/verify-localizations.sh` — compiled bundle and representative runtime lookup verifier.

**Modify for packaging:**

- `Makefile` — compile both catalogs into the app and invoke bundle verification.
- `Support/Info.plist` — advertise supported localizations.
- `Sources/OutcutShare/App.swift` — internal runtime localization probe used by verification.

**Modify for localized domain display values and errors:**

- `Sources/OutcutShare/FollowController.swift`
- `Sources/OutcutShare/Hotkeys.swift`
- `Sources/OutcutShare/SettingsStore.swift`
- `Sources/OutcutShare/MicCapture.swift`
- `Sources/OutcutShare/RecordingEngine.swift`

**Modify for localized production UI:**

- `Sources/OutcutShare/AppDelegate.swift`
- `Sources/OutcutShare/AppPicker.swift`
- `Sources/OutcutShare/CaptureResultPreview.swift`
- `Sources/OutcutShare/Hotbar.swift`
- `Sources/OutcutShare/LiveFrameWindow.swift`
- `Sources/OutcutShare/MonitorDrag.swift`
- `Sources/OutcutShare/PermissionsView.swift`
- `Sources/OutcutShare/PreviewWindow.swift`
- `Sources/OutcutShare/RegionMover.swift`
- `Sources/OutcutShare/RegionPreviewCanvas.swift`
- `Sources/OutcutShare/RegionSelector.swift`
- `Sources/OutcutShare/SettingsShortcutsPage.swift`
- `Sources/OutcutShare/SettingsView.swift`
- `Sources/OutcutShare/ShareSession.swift`
- `Sources/OutcutShare/StatusBarController.swift`

`DemoContent.swift` and `DemoHarness.swift` stay unchanged because they are
explicitly outside production localization scope.

---

### Task 1: Catalog Contract and Bundle Metadata

**Files:**

- Create: `Tests/OutcutShareTests/LocalizationCatalogTests.swift`
- Create: `Resources/Localization/Localizable.xcstrings`
- Create: `Resources/Localization/InfoPlist.xcstrings`
- Modify: `Support/Info.plist`

**Interfaces:**

- Consumes: JSON String Catalog schema version `1.0`.
- Produces: catalogs whose `sourceLanguage` is `en` and whose locale set is `["de", "en", "es", "fr", "ja", "zh-Hans"]`.

- [ ] **Step 1: Write the failing catalog contract test**

Add Codable fixtures that decode `sourceLanguage`, `strings`,
`localizations`, and `stringUnit`. Resolve the repository root from
`#filePath`, load both catalog JSON files, and assert:

```swift
private let supported = Set(["en", "de", "fr", "es", "zh-Hans", "ja"])

func testEveryAppStringIsFinalizedForEverySupportedLocale() throws {
    let catalog = try loadCatalog("Localizable")
    XCTAssertEqual(catalog.sourceLanguage, "en")
    for (key, entry) in catalog.strings {
        XCTAssertEqual(Set(entry.localizations.keys), supported, key)
        for locale in supported {
            let unit = try XCTUnwrap(entry.localizations[locale]?.stringUnit)
            XCTAssertEqual(unit.state, "translated", "\(key) [\(locale)]")
            XCTAssertFalse(unit.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}

func testInfoPlistAndCatalogLocaleSetsMatch() throws {
    let info = try loadInfoPlist()
    XCTAssertEqual(Set(try XCTUnwrap(info["CFBundleLocalizations"] as? [String])),
                   supported)
}
```

Also compare printf placeholder signatures after removing positional indexes so
`%1$@` and `%@` are compatible, while a missing `%d` fails.

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
swift test --filter LocalizationCatalogTests
```

Expected: FAIL because both catalogs are absent and `CFBundleLocalizations` is
not declared.

- [ ] **Step 3: Add the initial catalogs and bundle declarations**

Create valid catalogs with a seed key in all six languages:

```json
"menu.selectRegion": {
  "comment": "Menu command that begins selecting a region to share.",
  "extractionState": "manual",
  "localizations": {
    "en": { "stringUnit": { "state": "translated", "value": "Select Region & Share" } },
    "de": { "stringUnit": { "state": "translated", "value": "Bereich auswählen und teilen" } },
    "fr": { "stringUnit": { "state": "translated", "value": "Sélectionner une zone et partager" } },
    "es": { "stringUnit": { "state": "translated", "value": "Seleccionar región y compartir" } },
    "zh-Hans": { "stringUnit": { "state": "translated", "value": "选择区域并共享" } },
    "ja": { "stringUnit": { "state": "translated", "value": "範囲を選択して共有" } }
  }
}
```

Add `NSMicrophoneUsageDescription` to `InfoPlist.xcstrings` in all six locales.
Add the same locale codes as strings under `CFBundleLocalizations` in
`Support/Info.plist`.

- [ ] **Step 4: Run the focused and full tests**

Run:

```bash
swift test --filter LocalizationCatalogTests
swift test
```

Expected: PASS, including the original 181 tests.

- [ ] **Step 5: Commit**

```bash
git add Resources/Localization Support/Info.plist \
  Tests/OutcutShareTests/LocalizationCatalogTests.swift
git commit -m "test: define localization catalog contract"
```

---

### Task 2: Typed Localization Runtime

**Files:**

- Create: `Tests/OutcutShareTests/LocalizationTests.swift`
- Create: `Sources/OutcutShare/L10n.swift`
- Modify: `Resources/Localization/Localizable.xcstrings`

**Interfaces:**

- Produces: `enum L10n.Key: String`.
- Produces: `L10n.string(_ key: Key, bundle: Bundle = .main, localeIdentifier: String? = nil, arguments: [CVarArg] = []) -> String`.
- Produces: `L10n.localizedBundle(in bundle: Bundle, localeIdentifier: String?) -> Bundle`.

- [ ] **Step 1: Write failing lookup and formatting tests**

Create a temporary `.bundle` containing `en.lproj` and `de.lproj`
`Localizable.strings` files, then assert:

```swift
XCTAssertEqual(
    L10n.string(.menuSelectRegion, bundle: fixture, localeIdentifier: "de"),
    "Bereich auswählen und teilen"
)
XCTAssertEqual(
    L10n.string(.testFormattedCount, bundle: fixture, localeIdentifier: "de",
                arguments: [3]),
    "3 Elemente"
)
XCTAssertEqual(
    L10n.string(.menuSelectRegion, bundle: fixture, localeIdentifier: "it"),
    "Select Region & Share"
)
```

The fixture bundle has an Info.plist with `CFBundleDevelopmentRegion = en` and
the same six `CFBundleLocalizations`.

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
swift test --filter LocalizationTests
```

Expected: compile failure because `L10n` does not exist.

- [ ] **Step 3: Implement the minimal typed resolver**

Implement semantic enum cases and lookup:

```swift
enum L10n {
    enum Key: String {
        case menuSelectRegion = "menu.selectRegion"
        case testFormattedCount = "test.formattedCount"
    }

    static func string(
        _ key: Key,
        bundle: Bundle = .main,
        localeIdentifier: String? = nil,
        arguments: [CVarArg] = []
    ) -> String {
        let resolved = localizedBundle(in: bundle, localeIdentifier: localeIdentifier)
        let format = resolved.localizedString(forKey: key.rawValue,
                                              value: nil,
                                              table: "Localizable")
        guard !arguments.isEmpty else { return format }
        let locale = localeIdentifier.map(Locale.init(identifier:)) ?? .current
        return String(format: format, locale: locale, arguments: arguments)
    }
}
```

`localizedBundle` chooses the requested `.lproj`; when unsupported, it chooses
the development `en.lproj`; without an explicit locale it returns the incoming
bundle so Foundation applies macOS preferences.

- [ ] **Step 4: Run focused and full tests**

Run:

```bash
swift test --filter LocalizationTests
swift test
```

Expected: PASS with no warnings.

- [ ] **Step 5: Commit**

```bash
git add Sources/OutcutShare/L10n.swift \
  Tests/OutcutShareTests/LocalizationTests.swift \
  Resources/Localization/Localizable.xcstrings
git commit -m "feat: add typed localization runtime"
```

---

### Task 3: Localized Domain Labels and Menu/Permission Chrome

**Files:**

- Create: `Scripts/check-localization-source.sh`
- Modify: `Sources/OutcutShare/L10n.swift`
- Modify: `Resources/Localization/Localizable.xcstrings`
- Modify: `Sources/OutcutShare/FollowController.swift`
- Modify: `Sources/OutcutShare/Hotkeys.swift`
- Modify: `Sources/OutcutShare/SettingsStore.swift`
- Modify: `Sources/OutcutShare/StatusBarController.swift`
- Modify: `Sources/OutcutShare/PermissionsView.swift`
- Modify: `Sources/OutcutShare/AppPicker.swift`

**Interfaces:**

- Consumes: `L10n.string`.
- Produces: localized `FollowMode.displayName`, `HotkeyAction.displayName`, and `DragOutModifier.displayName` while preserving raw values.
- Produces: `Scripts/check-localization-source.sh [source-file ...]`.

- [ ] **Step 1: Add a failing targeted source lint**

The lint scans Swift source and detects literal English passed to
`Text`, `Button`, `Toggle`, `Picker`, `Label`, `Section`, `NSMenuItem`,
`NSMenu(title:)`, `.help`, `.accessibilityLabel`, alert title fields, window
titles, and `addButton(withTitle:)`. It ignores empty strings, system-symbol
names, format-only values, and exact technical constants. Implement it as a
developer lint, not an XCTest: it intentionally enforces a source convention
rather than claiming to test runtime behavior.

Start by scanning exactly the six files in this task. Keep persisted-value
behavior in the existing XCTest suite:

```swift
XCTAssertEqual(FollowMode.activeWindow.rawValue, "activeWindow")
XCTAssertEqual(HotkeyAction.togglePause.rawValue, "togglePause")
XCTAssertEqual(DragOutModifier.shift.rawValue, "shift")
```

- [ ] **Step 2: Run the audit and verify RED**

Run:

```bash
Scripts/check-localization-source.sh \
  Sources/OutcutShare/{FollowController,Hotkeys,SettingsStore,StatusBarController,PermissionsView,AppPicker}.swift
```

Expected: FAIL with current English menu, permission, picker, and enum display
strings listed by file and line.

- [ ] **Step 3: Add typed keys and all six translations**

Add semantic key groups for:

- `follow.*`, `hotkey.*`, and `modifier.*`;
- `menu.*`, including active/inactive variants and preset/capture commands;
- `presetPrompt.*`;
- `permissions.*`; and
- `appPicker.*`.

Every new key must include a translator comment and finalized values for all
six locales. Preserve keyboard glyphs and the product name.

- [ ] **Step 4: Replace literals with typed localization**

Use `L10n.string(.key)` for AppKit titles and `Text(L10n.string(.key))` /
`Button(L10n.string(.key))` for SwiftUI. For the default preset name use a
formatted catalog key such as `Preset %d`, never `"Preset " + number`.

- [ ] **Step 5: Run targeted, catalog, and full tests**

Run:

```bash
Scripts/check-localization-source.sh
swift test --filter LocalizationCatalogTests
swift test
```

Expected: PASS; raw-value assertions unchanged.

- [ ] **Step 6: Commit**

```bash
git add Sources/OutcutShare Resources/Localization/Localizable.xcstrings \
  Scripts/check-localization-source.sh
git commit -m "feat: localize menus and permissions"
```

---

### Task 4: Settings Localization

**Files:**

- Modify: `Sources/OutcutShare/L10n.swift`
- Modify: `Resources/Localization/Localizable.xcstrings`
- Modify: `Sources/OutcutShare/SettingsView.swift`
- Modify: `Sources/OutcutShare/SettingsShortcutsPage.swift`
- Modify: `Sources/OutcutShare/DimPreview.swift`
- Modify: `Sources/OutcutShare/RegionPreviewCanvas.swift`
- Modify: `Scripts/check-localization-source.sh`

**Interfaces:**

- Produces: localized `SettingsPage.title`.
- Produces: complete `settings.*`, `shortcuts.*`, and settings-preview keys.

- [ ] **Step 1: Expand the audit and verify RED**

Add all five settings files to the lint's default source list. Keep the existing
`SettingsPage.about` final-tab test and persisted enum raw-value tests unchanged.

Run:

```bash
Scripts/check-localization-source.sh
```

Expected: FAIL with settings section titles, labels, captions, tooltips, and
accessibility literals.

- [ ] **Step 2: Add full settings catalog groups**

Add translations for General, Appearance, Privacy, Recording, Presets,
Shortcuts, Permissions, and About. Add formatted keys for version, dimensions,
percentages, quality, and duplicate-shortcut warnings. Keep resolution tokens
and keyboard glyphs intact.

- [ ] **Step 3: Migrate settings without changing bindings**

Replace only presentation strings. Keep all `@Binding`, `.tag`, raw enum,
UserDefaults, notification, and settings-window teardown behavior unchanged.
Replace concatenated captions with single catalog sentences. Use substitutions
for values such as `Version %@`, `%d %%`, and `%d × %d`.

- [ ] **Step 4: Run targeted and full tests**

Run:

```bash
swift test --filter 'Localization|Settings'
swift test
```

Expected: PASS, including settings teardown tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/OutcutShare/SettingsView.swift \
  Sources/OutcutShare/SettingsShortcutsPage.swift \
  Sources/OutcutShare/DimPreview.swift \
  Sources/OutcutShare/RegionPreviewCanvas.swift \
  Sources/OutcutShare/L10n.swift \
  Resources/Localization/Localizable.xcstrings \
  Scripts/check-localization-source.sh
git commit -m "feat: localize settings"
```

---

### Task 5: Sharing, Overlay, Hotbar, and Preview Localization

**Files:**

- Modify: `Sources/OutcutShare/L10n.swift`
- Modify: `Resources/Localization/Localizable.xcstrings`
- Modify: `Sources/OutcutShare/Hotbar.swift`
- Modify: `Sources/OutcutShare/LiveFrameWindow.swift`
- Modify: `Sources/OutcutShare/MonitorDrag.swift`
- Modify: `Sources/OutcutShare/PreviewWindow.swift`
- Modify: `Sources/OutcutShare/RegionMover.swift`
- Modify: `Sources/OutcutShare/RegionSelector.swift`
- Modify: `Scripts/check-localization-source.sh`

**Interfaces:**

- Produces: `sharing.*`, `selector.*`, `hotbar.*`, `preview.*`, and
  `monitor.*` catalog groups.

- [ ] **Step 1: Expand the source lint and verify RED**

Add the six surface files to the lint and run:

```bash
Scripts/check-localization-source.sh
```

Expected: FAIL with current hover help, selection instructions, pause text,
monitor controls, preview controls, and window titles.

- [ ] **Step 2: Add all six translations for surface keys**

Keep instructions as complete sentences. Add variants for Pause/Resume,
Record/Stop, control-mode states, follow targets, window drag direction,
selection modifiers, save preset, preview visibility, OCR state, and hotbar
orientation/help. Preserve Space/Shift/Control glyphs where the code presents
physical keys.

- [ ] **Step 3: Replace surface literals**

Use formatted catalog keys for dimensions and state-dependent captions. Change
`PauseScreenContent.resolve` so its localized default is requested only when
the saved pause message is empty; never overwrite a saved custom message.
Keep system-symbol strings, drawing geometry, hit-testing labels used only as
internal dictionary keys, and accessibility action wiring unchanged.

- [ ] **Step 4: Run surface and full tests**

Run:

```bash
swift test --filter 'Localization|Preview|Hotbar|Monitor|Snapping'
swift test
```

Expected: PASS with no geometry/state regressions.

- [ ] **Step 5: Commit**

```bash
git add Sources/OutcutShare/{Hotbar,LiveFrameWindow,MonitorDrag,PreviewWindow,RegionMover,RegionSelector,L10n}.swift \
  Resources/Localization/Localizable.xcstrings \
  Scripts/check-localization-source.sh
git commit -m "feat: localize sharing controls"
```

---

### Task 6: Capture Card, OCR, and Trim Localization

**Files:**

- Modify: `Sources/OutcutShare/L10n.swift`
- Modify: `Resources/Localization/Localizable.xcstrings`
- Modify: `Sources/OutcutShare/CaptureResultPreview.swift`
- Modify: `Scripts/check-localization-source.sh`

**Interfaces:**

- Produces: `capture.*`, `ocr.*`, and `trim.*` catalog groups.

- [ ] **Step 1: Expand the source lint and verify RED**

Add `CaptureResultPreview.swift`; run the lint and expect all visible capture
card, delete, OCR, Quick Look, drag, trim, export, and error literals to fail.

- [ ] **Step 2: Add translated capture keys**

Use substitutions for filenames, durations, trim in/out times, progress,
export success/failure, and OCR results. Keep file paths and filenames
verbatim as arguments. Do not translate media extensions.

- [ ] **Step 3: Replace literals and preserve async behavior**

Swap presentation strings only. Do not change capture-card timers, hover
settling, drag providers, OCR tasks, trim ranges, AV export, delete behavior,
or window teardown.

- [ ] **Step 4: Run capture and full tests**

Run:

```bash
swift test --filter 'Localization|Capture|Trim'
swift test
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/OutcutShare/{CaptureResultPreview,L10n}.swift \
  Resources/Localization/Localizable.xcstrings \
  Scripts/check-localization-source.sh
git commit -m "feat: localize capture workflows"
```

---

### Task 7: Alerts and Application Error Localization

**Files:**

- Modify: `Sources/OutcutShare/L10n.swift`
- Modify: `Resources/Localization/Localizable.xcstrings`
- Modify: `Sources/OutcutShare/AppDelegate.swift`
- Modify: `Sources/OutcutShare/ShareSession.swift`
- Modify: `Sources/OutcutShare/MicCapture.swift`
- Modify: `Sources/OutcutShare/RecordingEngine.swift`
- Modify: `Scripts/check-localization-source.sh`

**Interfaces:**

- Produces: `alert.*`, `error.*`, and `recording.error.*` catalog groups.

- [ ] **Step 1: Add failing error and source checks**

Audit the four source files. Add focused assertions that locally-created
`NSError` descriptions no longer contain hard-coded English and that alert
buttons/titles resolve through `L10n`.

Run:

```bash
swift test --filter Localization
```

Expected: FAIL with alert and app-owned error literals.

- [ ] **Step 2: Add translated alert/error keys**

Translate Outcut Share's explanations for capture, recording, microphone,
virtual display, save, and OCR failures. Translate generic OK/Cancel/Delete/
Save actions. Leave operating-system `error.localizedDescription` intact when
the error originates outside the app.

- [ ] **Step 3: Replace app-owned error text**

Use `NSLocalizedDescriptionKey: L10n.string(.errorKey)` for existing NSError
construction and localized titles/buttons in every alert. Do not change error
domains/codes or control flow.

- [ ] **Step 4: Run error and full tests**

Run:

```bash
swift test --filter Localization
swift test
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/OutcutShare/{AppDelegate,ShareSession,MicCapture,RecordingEngine,L10n}.swift \
  Resources/Localization/Localizable.xcstrings \
  Scripts/check-localization-source.sh
git commit -m "feat: localize alerts and errors"
```

---

### Task 8: Catalog Compilation and Runtime Bundle Verification

**Files:**

- Modify: `Makefile`
- Modify: `Sources/OutcutShare/App.swift`
- Create: `Scripts/verify-localizations.sh`
- Modify: `Tests/OutcutShareTests/LocalizationCatalogTests.swift`

**Interfaces:**

- Produces: `--localization-test=<locale>` debug probe that prints
  `menu.selectRegion` and exits.
- Produces: `Scripts/verify-localizations.sh <app-path>`.

- [ ] **Step 1: Write failing build-verifier assertions**

The verifier checks:

```sh
locales="en de fr es zh-Hans ja"
for locale in $locales; do
  test -f "$app/Contents/Resources/$locale.lproj/Localizable.strings"
  test -f "$app/Contents/Resources/$locale.lproj/InfoPlist.strings"
done
```

It runs the bundled executable with each locale probe and compares exact values:

```text
en      Select Region & Share
de      Bereich auswählen und teilen
fr      Sélectionner une zone et partager
es      Seleccionar región y compartir
zh-Hans 选择区域并共享
ja      範囲を選択して共有
```

Run against the current app and verify failure because catalogs are not compiled.

- [ ] **Step 2: Add catalog compilation to `make app`**

Add both catalogs to app dependencies and compile each with:

```bash
xcrun xcstringstool compile Resources/Localization/Localizable.xcstrings \
  --output-directory build/OutcutShare.app/Contents/Resources
xcrun xcstringstool compile Resources/Localization/InfoPlist.xcstrings \
  --output-directory build/OutcutShare.app/Contents/Resources
```

Invoke the verifier after Info.plist stamping and before codesigning. Keep
existing asset compilation, stable signing, and version stamping unchanged.

- [ ] **Step 3: Add the internal runtime probe**

In `OutcutShareApp.main`, detect `--localization-test=<locale>` before creating
`NSApplication`, call:

```swift
print(L10n.string(.menuSelectRegion,
                  localeIdentifier: String(argument.dropFirst(prefix.count))))
```

and return. This output is test-only and deliberately not localized prose.

- [ ] **Step 4: Build and verify GREEN**

Run:

```bash
make app
Scripts/verify-localizations.sh build/OutcutShare.app
```

Expected: all six `.lproj` pairs exist, every probe matches, codesigning
succeeds, and the build emits zero warnings.

- [ ] **Step 5: Run full tests and commit**

Run:

```bash
swift test
git diff --check
```

Then:

```bash
git add Makefile Sources/OutcutShare/App.swift Scripts/verify-localizations.sh \
  Tests/OutcutShareTests/LocalizationCatalogTests.swift
git commit -m "build: package and verify localizations"
```

---

### Task 9: Complete Source Audit and Runtime Layout Verification

**Files:**

- Modify: `Scripts/check-localization-source.sh`
- Modify: `Resources/Localization/Localizable.xcstrings`
- Modify: any production source file identified by the final audit.

**Interfaces:**

- Produces: full production-source localization lint with only exact
  technical-literal allowlist entries.

- [ ] **Step 1: Audit every production source file**

Expand the source lint to every Swift file under `Sources/OutcutShare` except
`DemoContent.swift` and `DemoHarness.swift`. The allowlist may contain exact
literal plus reason for system symbols, protocol strings, identifiers, paths,
formats, and debug output. It must not exclude a whole production file.

Run:

```bash
Scripts/check-localization-source.sh
```

Expected: any missed production UI literal fails with file and line.

- [ ] **Step 2: Localize every legitimate finding**

For each user-facing finding, add a semantic typed key with all six finalized
translations and replace the literal. For each technical finding, add a narrow
exact allowlist entry documenting why translation would break behavior.

- [ ] **Step 3: Re-run catalog compiler and automated gates**

Run:

```bash
xcrun xcstringstool compile Resources/Localization/Localizable.xcstrings \
  --output-directory /tmp/outcut-localization-check
xcrun xcstringstool compile Resources/Localization/InfoPlist.xcstrings \
  --output-directory /tmp/outcut-localization-check
swift test
make app
Scripts/verify-localizations.sh build/OutcutShare.app
git diff --check
```

Expected: all commands pass, 181 original tests plus localization tests pass,
and the release app builds with zero warnings.

- [ ] **Step 4: Exercise locale-specific UI**

Launch the app with a temporary `AppleLanguages` override for each locale and
use existing debug flags:

```bash
defaults write com.outcutshare.app AppleLanguages -array de
build/OutcutShare.app/Contents/MacOS/OutcutShare \
  --show-settings=general --close-settings-after=2
```

Repeat for settings/permissions in `en`, `de`, `fr`, `es`, `zh-Hans`, and `ja`.
Capture screenshots where screen-recording permission permits and inspect for
English leaks, clipping, truncation, and broken substitutions. Remove the
temporary `AppleLanguages` value from `com.outcutshare.app` afterwards.

- [ ] **Step 5: Verify dynamic non-English states**

In German and Japanese, exercise menu Pause/Resume, Start/Stop Recording,
Zoom In/Out, hotbar help, and a capture-result card. Confirm state changes alter
only localized labels and do not restart or otherwise change sessions.

- [ ] **Step 6: Final commit**

```bash
git add Sources/OutcutShare Resources/Localization \
  Scripts/check-localization-source.sh
git commit -m "feat: complete app localization"
```

- [ ] **Step 7: Final branch audit**

Run:

```bash
git status --short
git log --oneline main..HEAD
swift test
make app
Scripts/verify-localizations.sh build/OutcutShare.app
```

Expected: clean feature worktree, complete commit series, all tests and bundle
verification green, no release/tag/merge performed.
