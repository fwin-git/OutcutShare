# Hot Bar Scaling — Design

Date: 2026-07-30
Status: approved via /goal directive (implement autonomously, user confirms in the running app)

## Goal

One Appearance setting that scales the floating hot bar: icon sizes, text
sizes, and the bar's in-panel tooltips and dropdown grow together. The
current sizes are the minimum; users who find the bar too small can scale
it up to 2×.

## Setting

- `SettingsStore.hotbarScale: Double`, default `1.0`, clamped to `1.0…2.0`
  (borderThickness clamp pattern). Persisted under the inline defaults key
  `"hotbarScale"`, loaded with the `object(forKey:) == nil ? 1.0 : double`
  idiom (a plain `double(forKey:)` would read 0 for unset keys).
- No restart required: `notifyChange()` → `settingsChangedNotification` →
  `ShareSession.settingsDidChange()` already ends its no-restart branch
  with `hotbar.refresh()`.

## Settings UI (General tab; revised 2026-07-30)

Originally shipped as its own Appearance section; the user moved it: the
slider lives in **General → Companions**, directly under the hotbar
toggle (disabled while the hotbar is off). One row: a `Slider` (1.0…2.0)
labeled "Hotbar size" with a right-aligned percent label reusing
`settings.appearance.percent`. The General page's hardcoded hosting
height (SettingsView.swift `pageController(for:)`) grows to fit.

The General preview's mini hot bar (`RegionPreviewCanvas.miniHotbar`,
shown with `showsHotbar: true` on the General page only) multiplies its
literals (font 6.5, spacing 4.5, padding 7/4) by `settings.hotbarScale`
so the preview reflects the setting live and proportionally.

New localized key (all ten locales, same commit, per docs/localization.md):

- `settings.general.hotbarSize` — "Hotbar size" (slider label)

## Language picker (added 2026-07-30)

Fallout from the localization QA: a stale per-app `AppleLanguages`
override left the app in Japanese with no UI to change it. New setting in
**General → System**: a "Language" dropdown with "System default" plus
the ten shipped locales shown as endonyms (`Locale.localizedString(
forIdentifier:)`, no translation needed). Backed by
`SettingsStore.appLanguage` ("" = system), which mirrors the choice into
the standard per-app `AppleLanguages` override — read by AppKit on next
launch (caption `settings.general.languageCaption` says so). Tracked
under its own `"appLanguage"` key because reading `AppleLanguages` back
falls through to the global domain when no override exists.

Keys: `settings.general.language`, `settings.general.languageSystem`,
`settings.general.languageCaption`. `L10n` gains `supportedLocales` and
`nativeLanguageName(for:)`.

### Live switching (added 2026-07-30)

A language change applies immediately, no relaunch: `L10n.languageOverride`
(set from `appLanguage.didSet` before `notifyChange()`) feeds every
`L10n.string` call without an explicit `localeIdentifier`; "System
default" resolves via `systemPreferredLocale()` (CFPreferences global-
domain read — process-cached `Locale` state would report the launch
language). Surfaces:

- SwiftUI settings pages re-render through their observed store;
  `PermissionsPage`/`AboutPage` observe it solely for this.
- Settings window tab labels/title: `SettingsWindowController` watches
  `settingsChangedNotification`, and on a language change removes and
  re-adds the (unchanged) tab items with new labels — toolbar buttons
  copy labels at insertion — deferred one runloop to avoid re-entering
  the picker's action.
- Status menu: `relocalize()` re-resolves all static item titles on every
  `menuNeedsUpdate` (dynamic ones were already re-set in `refresh()`).
- Hotbar: `refresh()` tracks the language and refits the panel (label
  widths change).
- Permissions window re-applies its title per `show()`.

System-provided panels (color picker, open/save) keep the launch language
until relaunch — the caption says so.

## Applying the scale to the bar

- `HotbarModel` gains `@Published var scale: CGFloat = 1`. Both
  `HotbarView` instantiations (live panel in `build()`, throwaway measuring
  controller in `measuredBarSize()`) share the model, so sizing and
  rendering see the same value automatically.
- `HotbarView` gets a helper `s(_ v: CGFloat) -> CGFloat` returning
  `v * model.scale`; every size literal in the bar runs through it: button
  icon font 15 / frame 22, grabber width 18, ✕ font 12, chevron font 8,
  dropdown fonts 9/10 and row metrics, tooltip padding and height 22,
  bar spacing 13 and paddings 14/10, divider 16, split-control spacings,
  dropdown container padding/radius, outer wrapper spacings, and the
  flyout placement offsets (they encode tooltip/menu geometry, e.g. 11 =
  half the 22 pt tooltip height, so they must scale with it).
- Semantic `.font(.caption)` (tooltip, follow label, dropdown rows) does
  not respond to a multiplier → becomes `.system(size: s(10))` (caption is
  10 pt on macOS, so 1.0 stays pixel-identical).
- `FollowMenuRow` receives the scale as a `let` (it's a separate private
  struct without model access).

## Resizing the panel on change

`HotbarController.refresh()` copies `settings.hotbarScale` onto the model;
when the value actually changed and the panel is visible it invalidates
`lastHorizontalSize` (the cached horizontal footprint is now stale), then
runs the `setContentSize(measuredBarSize())` + `position()` pair
(applyOrientation's pattern). `show()`'s existing measure/position after
`refresh()` covers the not-yet-visible case.

Out of scope: the capture-result preview card and notification banner keep
their own sizes; `Geometry` gap (12) and demo choreography are
size-agnostic already.

## Testing

- `SettingsStoreTests`: default 1.0, persistence across instances,
  clamping at both ends (0.5 → 1.0, 3.0 → 2.0).
- `LocalizationCatalogTests` + `Scripts/check-localization-source.sh` +
  `Scripts/verify-localizations.sh` (via `make app`) gate the new strings.
- Manual: relaunch, share a region, drag the slider — bar, tooltips and
  dropdown grow live; settings preview mini bar follows.

## Docs

`docs/settings.md` Appearance table gains a "Hot bar size" row
(100–200 %, default 100 %).
