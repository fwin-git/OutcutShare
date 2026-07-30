# Four-Locale Expansion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add complete Brazilian Portuguese, Korean, Traditional Chinese, and Italian application localizations to Outcut Share.

**Architecture:** Extend the existing Apple String Catalog contract from six to ten exact locales. Keep translated content entirely in the two catalogs, and make tests, bundle declarations, compilation, packaged-runtime probes, and visual QA agree on the same locale set.

**Tech Stack:** Swift 5, XCTest, Apple String Catalogs, `xcstringstool`, zsh, jq, Make, AppKit runtime QA.

## Global Constraints

- Supported locale identifiers become exactly `en`, `de`, `fr`, `es`, `zh-Hans`, `ja`, `pt-BR`, `ko`, `zh-Hant`, and `it`.
- English remains the development language and fallback.
- All 257 application keys and the microphone permission string must be finalized and non-empty in every locale.
- Preserve every existing translation unchanged.
- Preserve placeholder signatures exactly.
- Keep brand names, keyboard glyphs, filenames, extensions, protocol values, and technical units untranslated where identity requires it.
- Use neutral Traditional Chinese suitable for the `zh-Hant` script localization rather than a Taiwan-only locale.
- Do not add European Portuguese, runtime translation, dependencies, App Store metadata, or unrelated UI behavior.
- Preserve Swift 5, macOS 14 minimum deployment, Apple Development signing, and zero build warnings.
- Work only on `feature/i18n-localization`; do not push, release, or merge into `main`.

---

## File Map

**Modify:**

- `Tests/OutcutShareTests/LocalizationCatalogTests.swift` — authoritative ten-locale catalog, bundle, placeholder, and compiler contract.
- `Tests/OutcutShareTests/LocalizationTests.swift` — keep the unsupported-locale fixture semantically outside the supported set.
- `Resources/Localization/Localizable.xcstrings` — add four finalized values to all 257 application keys.
- `Resources/Localization/InfoPlist.xcstrings` — add four finalized microphone permission descriptions.
- `Support/Info.plist` — declare the four locales in `CFBundleLocalizations`.
- `Scripts/verify-localizations.sh` — require 20 tables and probe representative values for all ten locales.

**Retain unchanged:**

- `Sources/OutcutShare/L10n.swift` — locale selection already accepts exact locale identifiers.
- `Makefile` — both catalogs are already compiled generically.

---

### Task 1: Expand the Tested Locale Contract

**Files:**

- Modify: `Tests/OutcutShareTests/LocalizationCatalogTests.swift:23`
- Modify: `Tests/OutcutShareTests/LocalizationTests.swift:74-84`

**Interfaces:**

- Produces: `supportedLocales` containing the exact ten-locale set.
- Consumes: the existing catalog decoder and compiler integration test.

- [ ] **Step 1: Change the authoritative test locale set**

Replace the six-locale constant with:

```swift
private let supportedLocales = Set([
    "en", "de", "fr", "es", "zh-Hans", "ja",
    "pt-BR", "ko", "zh-Hant", "it",
])
```

In `testUnsupportedLocaleFallsBackToEnglishDevelopmentLocalization`, replace
the requested fixture locale `"it"` with `"nl"` so the test still describes a
locale outside the application-supported set.

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
swift test \
  --filter LocalizationCatalogTests/testEveryAppStringIsFinalizedForEverySupportedLocale
```

Expected: FAIL because catalog entries contain the original six locales and
are missing `pt-BR`, `ko`, `zh-Hant`, and `it`.

- [ ] **Step 3: Run the bundle-declaration test and verify RED**

Run:

```bash
swift test \
  --filter LocalizationCatalogTests/testInfoPlistDeclaresTheCatalogLocaleSet
```

Expected: FAIL because `Support/Info.plist` still declares six locales.

---

### Task 2: Add Finalized Catalog Translations

**Files:**

- Modify: `Resources/Localization/Localizable.xcstrings`
- Modify: `Resources/Localization/InfoPlist.xcstrings`

**Interfaces:**

- Produces: `pt-BR`, `ko`, `zh-Hant`, and `it` `stringUnit` values with
  `state: "translated"` for every catalog entry.
- Consumes: existing English values, semantic keys, translator comments, and
  placeholder signatures.

- [ ] **Step 1: Translate all application catalog entries**

For each of the 257 entries in `Localizable.xcstrings`, add finalized
`stringUnit` blocks for all four locale keys. For example,
`menu.selectRegion` becomes:

```json
"pt-BR": {
  "stringUnit": {
    "state": "translated",
    "value": "Selecionar região e compartilhar"
  }
},
"ko": {
  "stringUnit": {
    "state": "translated",
    "value": "영역 선택 및 공유"
  }
},
"zh-Hant": {
  "stringUnit": {
    "state": "translated",
    "value": "選取區域並分享"
  }
},
"it": {
  "stringUnit": {
    "state": "translated",
    "value": "Seleziona area e condividi"
  }
}
```

Use the semantic key and comment for context. Preserve `%@`, `%d`, and any
positional format tokens exactly. Preserve line breaks only where the English
value uses them.

- [ ] **Step 2: Translate the microphone permission description**

Add these finalized values to `InfoPlist.xcstrings`:

```text
pt-BR: As gravações incluem o áudio do microfone quando essa opção está ativada em Ajustes → Gravação.
ko: 설정 → 녹화에서 활성화하면 녹화에 마이크 오디오가 포함됩니다.
zh-Hant: 在「設定」→「錄製」中啟用後，錄製內容會包含麥克風音訊。
it: Le registrazioni includono l’audio del microfono quando è abilitato in Impostazioni → Registrazione.
```

- [ ] **Step 3: Validate catalog structure and placeholder preservation**

Run:

```bash
jq empty Resources/Localization/Localizable.xcstrings \
  Resources/Localization/InfoPlist.xcstrings
swift test --filter LocalizationCatalogTests/testEveryAppStringIsFinalizedForEverySupportedLocale
swift test --filter LocalizationCatalogTests/testEveryInfoPlistStringIsFinalizedForEverySupportedLocale
swift test --filter LocalizationCatalogTests/testTranslationsPreserveFormatPlaceholderSignatures
```

Expected: the two completeness tests and the placeholder test PASS.

- [ ] **Step 4: Review translation consistency**

Export key, English, and new-locale values with:

```bash
jq -r '
  .strings
  | to_entries[]
  | [
      .key,
      .value.localizations.en.stringUnit.value,
      .value.localizations["pt-BR"].stringUnit.value,
      .value.localizations.ko.stringUnit.value,
      .value.localizations["zh-Hant"].stringUnit.value,
      .value.localizations.it.stringUnit.value
    ]
  | @tsv
' Resources/Localization/Localizable.xcstrings
```

Review every row for consistent sharing, recording, preset, permission,
pause/resume, follow-mode, and virtual-display terminology. Legitimately
unchanged brand and technical values are allowed; user-facing prose must not
silently copy the English fallback.

---

### Task 3: Complete Bundle and Packaged-Runtime Coverage

**Files:**

- Modify: `Support/Info.plist`
- Modify: `Scripts/verify-localizations.sh`

**Interfaces:**

- Produces: a ten-locale `CFBundleLocalizations` declaration.
- Produces: packaged verification of 20 `.strings` tables and ten executable
  localization probes.
- Consumes: the `--localization-test=LOCALE` debug argument in `AppDelegate`.

- [ ] **Step 1: Declare all four locales in the bundle**

Append these values after the existing locale declarations:

```xml
<string>pt-BR</string>
<string>ko</string>
<string>zh-Hant</string>
<string>it</string>
```

- [ ] **Step 2: Extend the packaged verifier**

Set:

```zsh
locales=(en de fr es zh-Hans ja pt-BR ko zh-Hant it)
```

Append representative values in matching order:

```zsh
"Selecionar região e compartilhar"
"영역 선택 및 공유"
"選取區域並分享"
"Seleziona area e condividi"
```

- [ ] **Step 3: Verify GREEN for declarations and compiled tables**

Run:

```bash
swift test --filter LocalizationCatalogTests/testInfoPlistDeclaresTheCatalogLocaleSet
swift test --filter LocalizationCatalogTests/testCatalogCompilerProducesEveryRuntimeTable
zsh -n Scripts/verify-localizations.sh
```

Expected: all commands PASS; catalog compilation produces both tables for all
ten locales.

- [ ] **Step 4: Run localization static gates**

Run:

```bash
Scripts/check-localization-source.sh
jq empty Resources/Localization/Localizable.xcstrings \
  Resources/Localization/InfoPlist.xcstrings
git diff --check
```

Expected: all commands PASS.

- [ ] **Step 5: Run the complete Swift suite**

Run:

```bash
swift test
```

Expected: all tests PASS with zero failures and zero build warnings.

- [ ] **Step 6: Commit the locale expansion**

Run:

```bash
git add Tests/OutcutShareTests/LocalizationCatalogTests.swift \
  Tests/OutcutShareTests/LocalizationTests.swift \
  Resources/Localization/Localizable.xcstrings \
  Resources/Localization/InfoPlist.xcstrings \
  Support/Info.plist \
  Scripts/verify-localizations.sh
git commit -m "feat: add Portuguese, Korean, Chinese, and Italian localizations"
```

---

### Task 4: Verify the Signed Application and New-Locale Layouts

**Files:**

- Verify: `build/OutcutShare.app`
- Produce temporarily: General and Permissions screenshots for `pt-BR`,
  `ko`, `zh-Hant`, and `it`

**Interfaces:**

- Consumes: the committed ten-locale catalogs and bundle metadata.
- Produces: signed runtime evidence and eight visually reviewed screenshots.

- [ ] **Step 1: Build and verify the signed app**

Run:

```bash
make -B app
Scripts/verify-localizations.sh build/OutcutShare.app
codesign --verify --deep --strict --verbose=2 build/OutcutShare.app
```

Expected: the release build has no warnings, all ten locale probes match, and
the app satisfies its designated requirement.

- [ ] **Step 2: Confirm all 20 runtime tables**

Run:

```bash
find build/OutcutShare.app/Contents/Resources \
  -type f \( -name Localizable.strings -o -name InfoPlist.strings \) \
  | sort
```

Expected: exactly two files in each of `en.lproj`, `de.lproj`, `fr.lproj`,
`es.lproj`, `zh-Hans.lproj`, `ja.lproj`, `pt-BR.lproj`, `ko.lproj`,
`zh-Hant.lproj`, and `it.lproj`.

- [ ] **Step 3: Capture isolated runtime layouts**

Copy the app to a temporary directory, give the copy a temporary bundle
identifier, re-sign it ad hoc, and use that identifier's `AppleLanguages`
default to launch:

```text
--show-settings=general
--show-settings=permissions
```

under `pt-BR`, `ko`, `zh-Hant`, and `it`. Locate each settings window by its
process ID with `CGWindowListCopyWindowInfo`, capture it with
`screencapture -l`, then terminate only that temporary process and remove the
temporary defaults value.

- [ ] **Step 4: Inspect all eight screenshots**

Confirm the requested locale is active, all eight toolbar tabs are visible,
and no user-facing copy is clipped, overlapping, unexpectedly English, or
showing a malformed placeholder.

- [ ] **Step 5: Final branch audit**

Run:

```bash
git status --short --branch
git diff --check
git merge-base --is-ancestor main HEAD
git log --oneline --decorate --graph --max-count=15
```

Expected: clean `feature/i18n-localization`, `main` remains an ancestor, and
the design, plan, and locale-expansion commits are visible. Do not push,
release, or merge into `main`.
