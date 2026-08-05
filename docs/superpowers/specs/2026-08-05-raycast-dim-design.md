# Raycast Dim Control — Design

Date: 2026-08-05
Status: approved (UX, presets and semantics chosen by the user)

## Goal

Change the outside-region dim strength from Raycast: preset values or a
manually typed percent, without opening the settings window.

## URL grammar (first numeric command)

`outcutshare://dim?percent=NN`

- `percent` parses as Double, valid range 0–100. Missing, non-numeric,
  negative or > 100 → `URLCommand.parse` returns nil and the URL is
  silently ignored (existing malformed-URL invariant).
- Handler semantics (AppDelegate.handle):
  - `percent == 0` → `settings.dimmingEnabled = false`; the stored
    `dimOpacity` stays untouched.
  - `percent > 0` → `settings.dimOpacity = percent / 100` and
    `settings.dimmingEnabled = true`. Values above the slider max clamp
    to 0.9 via the store's existing didSet clamp.
- New `URLCommand` case: `dim(percent: Double)`. Parameter name is
  lower-cased by the existing parser; the numeric value needs no
  case-insensitive matching.
- Applies live during a share: the dim overlay redraws on
  `settingsChangedNotification` and exists unconditionally for region
  sessions; no restart path is touched. Virtual Monitor sessions have no
  overlay (unchanged from toggle-dimming). No new alerts → no new
  localized strings.

## Raycast command

`set-dim-amount` (`view` mode, `raycast/src/set-dim-amount.tsx`),
title "Set Dim Amount", description "Set the outside-region dim
strength, or turn dimming off." — List pattern of `set-share-mode.tsx`.

- Presets section: Off, 20 %, 40 %, 60 %, 80 %. Off sends
  `dim?percent=0` (Icon.CircleDisabled); values send their percent
  (Icon.Moon).
- Manual input: `onSearchTextChange` keeps the typed text; when it parses
  to a number 0–90 a "Set to N %" row appears in a section above the
  presets, sending `dim?percent=N`. Default list filtering stays on (the
  dynamic row always matches the typed text).
- Current-state checkmark accessory: the preset matching
  `round(dimOpacity * 100)` when dimming is on, Off when disabled.
- HUDs: `Dim N %` / `Dimming off`.

## Raycast state reading

`raycast/src/plist.ts` gains `extractRealKey` (`<real>` tag; widen
`extractValue`'s tag union) and `extractBoolKey` (`<true/>`/`<false/>`
self-closing tags). `AppState` gains `dimPercent: number` and
`dimmingEnabled: boolean` with fallbacks 60 / true — the app's registered
defaults, which never appear in `defaults export`.

## Tests

- `URLCommandsTests`: `dim?percent=45` → `.dim(percent: 45)`, decimals,
  case-insensitive command/param name, missing/non-numeric/negative/>100
  → nil.
- `SettingsStore` clamp behavior is already covered.
- `raycast/tests/plist.test.ts`: real + bool extraction, missing keys.
- Manual: `open "outcutshare://dim?percent=45"` against the running app
  mid-share; Raycast `npm run typecheck` + `npm test`.

## Docs (grammar, extension and docs move together — AGENTS.md)

`docs/raycast.md`: command-table row, URL-table row
(`outcutshare://dim?percent=0-100`, 0 = off, > 0 sets and enables,
clamps at 90, local-only), extend the malformed-URL sentence to cover
the numeric parameter, and revise the "style and appearance settings
stay in the app" boundary sentence which this feature deliberately
crosses.
