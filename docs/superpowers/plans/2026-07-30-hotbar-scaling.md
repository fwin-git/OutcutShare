# Hot Bar Scaling — Implementation Plan

Spec: `docs/superpowers/specs/2026-07-30-hotbar-scaling-design.md`
Branch: `feature/hotbar-scaling`

## Task 1 — Store + tests

1. Failing tests in `Tests/OutcutShareTests/SettingsStoreTests.swift`:
   default `hotbarScale == 1.0`, persistence across instances, clamps
   `0.5 → 1.0` and `3.0 → 2.0`.
2. `SettingsStore.hotbarScale` (`didSet` clamp 1…2 + `defaults.set` +
   `notifyChange()`, inline key `"hotbarScale"`); load in `init` with the
   `object(forKey:) == nil ? 1.0 : double(forKey:)` idiom.
3. `swift test --filter SettingsStoreTests` green.

## Task 2 — Localized strings

1. `L10n.Key`: `settingsAppearanceHotbar = "settings.appearance.hotbar"`,
   `settingsAppearanceHotbarSize = "settings.appearance.hotbarSize"`.
2. Both keys in `Resources/Localization/Localizable.xcstrings` with all
   ten locales translated ("Hot bar" / "Size" et al.).
3. `swift test --filter LocalizationCatalogTests` and
   `Scripts/check-localization-source.sh` green.

## Task 3 — Appearance UI

1. New Section in `AppearancePage` after Border: slider 1.0…2.0 bound to
   `$settings.hotbarScale` + percent label (`settings.appearance.percent`).
2. Appearance hosting height 780 → 870 in `pageController(for:)`.
3. `RegionPreviewCanvas.miniHotbar` literals × `settings.hotbarScale`.

## Task 4 — Hot bar applies the scale

1. `HotbarModel.scale`; `HotbarView.s(_:)` helper; run every size literal
   through it (fonts, frames, paddings, spacings, flyout offsets);
   `.caption` → `.system(size: s(10))`; `FollowMenuRow` gets `scale` let.
2. `HotbarController.refresh()`: on scale change, invalidate
   `lastHorizontalSize`; if visible, `setContentSize(measuredBarSize())` +
   `position()`.

## Task 5 — Docs + gates + ship

1. `docs/settings.md` Appearance table row.
2. `make test`, `make app` (runs verify-localizations), commit, merge to
   main, `pkill -x OutcutShare`, `open build/OutcutShare.app`.
