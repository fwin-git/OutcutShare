# Raycast Extension + outcutshare:// URL Scheme Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Trigger Outcut Share's main actions (select/share, last region, presets, stop, pause, record, follow mode, share mode, presenter toggles) from Raycast via a new `outcutshare://` URL scheme.

**Architecture:** The app gains a URL scheme: a pure `URLCommand` parser plus an Apple-Event handler in `AppDelegate` that dispatches to the existing `ShareSession` / `SettingsStore` APIs (exactly like the hotkey dispatcher). A TypeScript Raycast extension in `raycast/` opens those URLs; its three list commands read current presets / follow mode / share mode from the app's UserDefaults via `defaults export`.

**Tech Stack:** Swift 5 (SwiftPM, XCTest), TypeScript + `@raycast/api` (the `ray` CLI ships with it), `node --test` via `tsx`.

Spec: `docs/superpowers/specs/2026-07-28-raycast-extension-design.md`.

## Global Constraints

- Branch: `feature/raycast-extension` (exists). Never commit to `main`; merge `--no-ff` at the end. NEVER cut a release.
- Zero build warnings (`make app` and `swift test` output must be warning-free).
- Comments state non-obvious constraints only.
- The user's release app runs from `build/OutcutShare.app` on their real defaults domain `com.outcutshare.app`. E2E steps that change settings MUST restore the previous value, and MUST change settings through the app (URL commands), never `defaults write`, while the app runs (cfprefsd cache).
- App bundle id: `com.outcutshare.app`. URL scheme: `outcutshare`.
- After the milestone: `make app && pkill -x OutcutShare; open build/OutcutShare.app`.

---

### Task 1: URLCommand parser + preset matcher (Swift, TDD)

**Files:**
- Create: `Sources/OutcutShare/URLCommands.swift`
- Modify: `Sources/OutcutShare/SettingsStore.swift:69` (`enum ShareMode: String {` → add `CaseIterable`)
- Test: `Tests/OutcutShareTests/URLCommandsTests.swift`

**Interfaces:**
- Consumes: `FollowMode` (String, CaseIterable; raws `off|activeWindow|cursor`), `ShareMode` (String; raws `virtualDisplay|hiddenWindow|virtualMonitor`), `RegionPreset` (`id: UUID`, `name: String`).
- Produces: `URLCommand.parse(_ url: URL) -> URLCommand?`; `URLCommand.matchPreset(id: String?, name: String?, in: [RegionPreset]) -> RegionPreset?`; `enum URLToggleOption: String, CaseIterable { case preview, hotbar, cursorHighlights, dimming }`; cases `.select, .shareLast, .preset(id:name:), .stop, .togglePause, .toggleRecording, .follow(FollowMode), .shareMode(ShareMode), .toggle(URLToggleOption)`.

- [ ] **Step 1: Write the failing test**

`Tests/OutcutShareTests/URLCommandsTests.swift`:

```swift
import XCTest
@testable import OutcutShare

final class URLCommandsTests: XCTestCase {
    private func parse(_ s: String) -> URLCommand? {
        URLCommand.parse(URL(string: s)!)
    }

    func testSimpleCommands() {
        XCTAssertEqual(parse("outcutshare://select"), .select)
        XCTAssertEqual(parse("outcutshare://share-last"), .shareLast)
        XCTAssertEqual(parse("outcutshare://stop"), .stop)
        XCTAssertEqual(parse("outcutshare://pause"), .togglePause)
        XCTAssertEqual(parse("outcutshare://record"), .toggleRecording)
    }

    func testCommandNameIsCaseInsensitive() {
        XCTAssertEqual(parse("outcutshare://Share-Last"), .shareLast)
    }

    func testPresetRequiresIdOrName() {
        XCTAssertEqual(parse("outcutshare://preset?id=ABC"), .preset(id: "ABC", name: nil))
        XCTAssertEqual(parse("outcutshare://preset?name=Demo"), .preset(id: nil, name: "Demo"))
        XCTAssertEqual(parse("outcutshare://preset?id=ABC&name=Demo"),
                       .preset(id: "ABC", name: "Demo"))
        XCTAssertNil(parse("outcutshare://preset"))
    }

    func testPresetNameIsPercentDecoded() {
        XCTAssertEqual(parse("outcutshare://preset?name=Left%20Half"),
                       .preset(id: nil, name: "Left Half"))
    }

    func testFollowModes() {
        XCTAssertEqual(parse("outcutshare://follow?mode=off"), .follow(.off))
        XCTAssertEqual(parse("outcutshare://follow?mode=activeWindow"), .follow(.activeWindow))
        XCTAssertEqual(parse("outcutshare://follow?mode=CURSOR"), .follow(.cursor))
        XCTAssertNil(parse("outcutshare://follow?mode=nope"))
        XCTAssertNil(parse("outcutshare://follow"))
    }

    func testShareModes() {
        XCTAssertEqual(parse("outcutshare://share-mode?mode=virtualDisplay"),
                       .shareMode(.virtualDisplay))
        XCTAssertEqual(parse("outcutshare://share-mode?mode=hiddenwindow"),
                       .shareMode(.hiddenWindow))
        XCTAssertEqual(parse("outcutshare://share-mode?mode=virtualMonitor"),
                       .shareMode(.virtualMonitor))
        XCTAssertNil(parse("outcutshare://share-mode?mode=fullscreen"))
    }

    func testToggleOptions() {
        XCTAssertEqual(parse("outcutshare://toggle?option=preview"), .toggle(.preview))
        XCTAssertEqual(parse("outcutshare://toggle?option=hotbar"), .toggle(.hotbar))
        XCTAssertEqual(parse("outcutshare://toggle?option=cursorhighlights"),
                       .toggle(.cursorHighlights))
        XCTAssertEqual(parse("outcutshare://toggle?option=dimming"), .toggle(.dimming))
        XCTAssertNil(parse("outcutshare://toggle?option=styles"))
        XCTAssertNil(parse("outcutshare://toggle"))
    }

    func testRejectsUnknownCommandAndForeignScheme() {
        XCTAssertNil(parse("outcutshare://quit"))
        XCTAssertNil(parse("https://select"))
    }

    // MARK: matchPreset

    private let presets = [
        RegionPreset(id: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!,
                     name: "Left Half",
                     region: StoredRegion(rect: CGRect(x: 0, y: 0, width: 800, height: 600),
                                          displayID: 1),
                     shareModeRaw: "hiddenWindow"),
        RegionPreset(id: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000002")!,
                     name: "left half",
                     region: StoredRegion(rect: CGRect(x: 0, y: 0, width: 400, height: 300),
                                          displayID: 1),
                     shareModeRaw: "hiddenWindow"),
    ]

    func testMatchPresetByIdWinsOverName() {
        let match = URLCommand.matchPreset(
            id: "aaaaaaaa-0000-0000-0000-000000000002", name: "Left Half", in: presets)
        XCTAssertEqual(match?.name, "left half")
    }

    func testMatchPresetExactNameBeatsCaseInsensitive() {
        XCTAssertEqual(URLCommand.matchPreset(id: nil, name: "left half", in: presets)?.id,
                       presets[1].id)
    }

    func testMatchPresetFallsBackCaseInsensitively() {
        XCTAssertEqual(URLCommand.matchPreset(id: nil, name: "LEFT HALF", in: presets)?.id,
                       presets[0].id)
    }

    func testMatchPresetNoMatchReturnsNil() {
        XCTAssertNil(URLCommand.matchPreset(id: "nope", name: nil, in: presets))
        XCTAssertNil(URLCommand.matchPreset(id: nil, name: nil, in: presets))
    }
}
```

(The fixtures use `StoredRegion.init(rect:displayID:)` and `RegionPreset`'s memberwise init — both exist in `Presets.swift` as of this plan; do not change `Presets.swift`.)

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter URLCommandsTests 2>&1 | tail -5`
Expected: compile error — `URLCommand` not found.

- [ ] **Step 3: Add `CaseIterable` to ShareMode and write the implementation**

In `Sources/OutcutShare/SettingsStore.swift` change line 69 `enum ShareMode: String {` to `enum ShareMode: String, CaseIterable {`.

`Sources/OutcutShare/URLCommands.swift`:

```swift
import Foundation

/// Presenter options togglable via outcutshare://toggle?option=…
enum URLToggleOption: String, CaseIterable {
    case preview
    case hotbar
    case cursorHighlights
    case dimming
}

/// Commands accepted over the outcutshare:// URL scheme (Raycast, shell,
/// any automation tool). Grammar documented in docs/raycast.md.
enum URLCommand: Equatable {
    case select
    case shareLast
    case preset(id: String?, name: String?)
    case stop
    case togglePause
    case toggleRecording
    case follow(FollowMode)
    case shareMode(ShareMode)
    case toggle(URLToggleOption)

    static func parse(_ url: URL) -> URLCommand? {
        guard url.scheme?.lowercased() == "outcutshare" else { return nil }
        let command = url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var params: [String: String] = [:]
        for item in URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [] {
            params[item.name.lowercased()] = item.value
        }
        switch command.lowercased() {
        case "select": return .select
        case "share-last": return .shareLast
        case "preset":
            let id = params["id"], name = params["name"]
            guard id != nil || name != nil else { return nil }
            return .preset(id: id, name: name)
        case "stop": return .stop
        case "pause": return .togglePause
        case "record": return .toggleRecording
        case "follow":
            guard let mode = params["mode"].flatMap(FollowMode.init(caseInsensitive:))
            else { return nil }
            return .follow(mode)
        case "share-mode":
            guard let mode = params["mode"].flatMap(ShareMode.init(caseInsensitive:))
            else { return nil }
            return .shareMode(mode)
        case "toggle":
            guard let option = params["option"].flatMap(URLToggleOption.init(caseInsensitive:))
            else { return nil }
            return .toggle(option)
        default:
            return nil
        }
    }

    /// id (exact UUID string, any case) wins; then exact name, then the
    /// first case-insensitive name match.
    static func matchPreset(id: String?, name: String?,
                            in presets: [RegionPreset]) -> RegionPreset? {
        if let id, let match = presets.first(where: {
            $0.id.uuidString.caseInsensitiveCompare(id) == .orderedSame }) {
            return match
        }
        guard let name else { return nil }
        return presets.first { $0.name == name }
            ?? presets.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }
}

extension RawRepresentable where Self: CaseIterable, RawValue == String {
    fileprivate init?(caseInsensitive raw: String) {
        guard let match = Self.allCases.first(where: {
            $0.rawValue.caseInsensitiveCompare(raw) == .orderedSame }) else { return nil }
        self = match
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter URLCommandsTests 2>&1 | tail -5`
Expected: all tests PASS, zero warnings. Also run the full suite once: `swift test 2>&1 | tail -3` (no regressions).

- [ ] **Step 5: Commit**

```bash
git add Sources/OutcutShare/URLCommands.swift Sources/OutcutShare/SettingsStore.swift Tests/OutcutShareTests/URLCommandsTests.swift
git commit -m "feat: parse outcutshare:// URL commands"
```

---

### Task 2: URL scheme registration + dispatch + E2E

**Files:**
- Modify: `Support/Info.plist` (add CFBundleURLTypes before closing `</dict>`)
- Modify: `Sources/OutcutShare/AppDelegate.swift` (handler + dispatch)
- Modify: `Sources/OutcutShare/ShareSession.swift` (add `isIdle` next to `isActive`, ~line 28)

**Interfaces:**
- Consumes: `URLCommand.parse`, `URLCommand.matchPreset` (Task 1); `ShareSession` methods `startSelection() / shareLastRegion() / sharePreset(_:) / stop() / togglePause() / toggleRecording() / setFollow(mode:)`; `SettingsStore.shared` vars `presets, shareMode, previewWindowEnabled, hotbarEnabled, cursorHighlight, clickRipples, dimmingEnabled`.
- Produces: the live `outcutshare://` scheme the Raycast extension targets.

- [ ] **Step 1: Register the scheme in Info.plist**

Insert into `Support/Info.plist` before the final `</dict>`:

```xml
	<key>CFBundleURLTypes</key>
	<array>
		<dict>
			<key>CFBundleURLName</key>
			<string>com.outcutshare.app.url</string>
			<key>CFBundleURLSchemes</key>
			<array>
				<string>outcutshare</string>
			</array>
		</dict>
	</array>
```

- [ ] **Step 2: Add `isIdle` to ShareSession**

Next to `var isActive: Bool { state == .active }` add:

```swift
    var isIdle: Bool { state == .idle }
```

- [ ] **Step 3: Add handler + dispatch to AppDelegate**

Add inside `final class AppDelegate` (above `applicationDidFinishLaunching`):

```swift
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Registered before didFinishLaunching so deep links that *launch*
        // the app (open outcutshare://…) are delivered too.
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleGetURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL))
    }

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor,
                                    withReplyEvent reply: NSAppleEventDescriptor) {
        guard let urlString = event
                .paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: urlString),
              let command = URLCommand.parse(url) else { return }
        handle(command)
    }

    private func handle(_ command: URLCommand) {
        let settings = SettingsStore.shared
        switch command {
        case .select: session.startSelection()
        case .shareLast: session.shareLastRegion()
        case .preset(let id, let name):
            if let preset = URLCommand.matchPreset(id: id, name: name,
                                                   in: settings.presets) {
                session.sharePreset(preset)
            } else {
                presentURLError("No preset matches \"\(name ?? id ?? "")\".")
            }
        case .stop: session.stop()
        case .togglePause: session.togglePause()
        case .toggleRecording: session.toggleRecording()
        case .follow(let mode): session.setFollow(mode: mode)
        case .shareMode(let mode):
            guard session.isIdle else {
                presentURLError("Stop sharing first to switch the share mode.")
                return
            }
            settings.shareMode = mode
        case .toggle(let option):
            switch option {
            case .preview: settings.previewWindowEnabled.toggle()
            case .hotbar: settings.hotbarEnabled.toggle()
            case .cursorHighlights:
                // Halo and ripples act as one presenter switch externally.
                let enabled = !settings.cursorHighlight
                settings.cursorHighlight = enabled
                settings.clickRipples = enabled
            case .dimming: settings.dimmingEnabled.toggle()
            }
        }
    }

    private func presentURLError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Outcut Share"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
```

- [ ] **Step 4: Build, relaunch, E2E the headlessly-verifiable routes**

```bash
make app 2>&1 | grep -i warning   # expect no output
pkill -x OutcutShare; open build/OutcutShare.app && sleep 2
# capture current values to restore later:
defaults read com.outcutshare.app shareMode; defaults read com.outcutshare.app followMode
# follow mode round-trip:
open "outcutshare://follow?mode=cursor" && sleep 1 && defaults read com.outcutshare.app followMode   # → cursor
open "outcutshare://follow?mode=off"    && sleep 1 && defaults read com.outcutshare.app followMode   # → off (or original)
# share mode while idle + restore:
open "outcutshare://share-mode?mode=virtualMonitor" && sleep 1 && defaults read com.outcutshare.app shareMode  # → virtualMonitor
open "outcutshare://share-mode?mode=<original>"     && sleep 1 && defaults read com.outcutshare.app shareMode  # → original
# each toggle twice (flips back), verify the value flips:
defaults read com.outcutshare.app previewWindowEnabled
open "outcutshare://toggle?option=preview" && sleep 1 && defaults read com.outcutshare.app previewWindowEnabled
open "outcutshare://toggle?option=preview" && sleep 1 && defaults read com.outcutshare.app previewWindowEnabled
# same pattern for hotbar / cursorHighlights (checks cursorHighlight AND clickRipples) / dimming
# malformed URL must do nothing visible:
open "outcutshare://toggle?option=styles"
```

Expected: every `defaults read` matches the comment; all values restored afterwards.

- [ ] **Step 5: E2E the visual routes**

```bash
open "outcutshare://select" && sleep 1 && screencapture -x /tmp/url-select.png
open "outcutshare://stop"   && sleep 1 && screencapture -x /tmp/url-stop.png
```

Inspect: selection overlay visible in the first shot, gone in the second. If `stop` doesn't dismiss the overlay (it guards `state != .idle`, so it should), ask the user to press Esc and note the finding. `share-last`, `preset`, `pause`, `record` need a real share — verified with the user in Task 7; the parser and dispatch paths are identical, so risk is low.

- [ ] **Step 6: Commit**

```bash
git add Support/Info.plist Sources/OutcutShare/AppDelegate.swift Sources/OutcutShare/ShareSession.swift
git commit -m "feat: outcutshare:// URL scheme triggers sharing actions remotely"
```

---

### Task 3: Raycast extension scaffold + the nine no-view commands

**Files:**
- Create: `raycast/package.json`, `raycast/tsconfig.json`, `raycast/.gitignore`, `raycast/assets/icon.png` (from `Resources/AppIcon.png`), `raycast/src/outcut.ts`, and one file per command: `raycast/src/share-last.ts`, `select-region.ts`, `stop-sharing.ts`, `toggle-pause.ts`, `toggle-recording.ts`, `toggle-preview.ts`, `toggle-hotbar.ts`, `toggle-cursor-highlights.ts`, `toggle-dimming.ts`

**Interfaces:**
- Produces: `send(pathAndQuery: string, hud: string): Promise<void>` in `src/outcut.ts` (used by all commands incl. Task 5's views); the command names above are referenced by `package.json`.

- [ ] **Step 1: Scaffold**

`raycast/.gitignore`:

```
node_modules/
dist/
```

`raycast/package.json`:

```json
{
  "$schema": "https://www.raycast.com/schemas/extension.json",
  "name": "outcut-share",
  "title": "Outcut Share",
  "description": "Control Outcut Share: share regions and presets, pause, record, switch follow and share modes.",
  "icon": "icon.png",
  "author": "fwin",
  "license": "MIT",
  "commands": [
    { "name": "share-last", "title": "Share Last Region", "description": "Re-share the most recent region.", "mode": "no-view" },
    { "name": "select-region", "title": "Select Region & Share", "description": "Start the drag-selection overlay (or the Virtual Monitor when that share mode is active).", "mode": "no-view" },
    { "name": "share-preset", "title": "Share Preset", "description": "Pick a saved region preset and share it.", "mode": "view" },
    { "name": "stop-sharing", "title": "Stop Sharing", "description": "End the current share session.", "mode": "no-view" },
    { "name": "toggle-pause", "title": "Pause / Resume Sharing", "description": "Freeze or blur what viewers see.", "mode": "no-view" },
    { "name": "toggle-recording", "title": "Start / Stop Recording", "description": "Record the shared region to an .mp4.", "mode": "no-view" },
    { "name": "set-follow-mode", "title": "Set Follow Mode", "description": "Region follows the active window, the cursor, or nothing.", "mode": "view" },
    { "name": "set-share-mode", "title": "Set Share Mode", "description": "Hidden Window, Virtual Display or Virtual Monitor (applies while not sharing).", "mode": "view" },
    { "name": "toggle-preview", "title": "Toggle Preview Window", "description": "Show or hide the floating viewers-see-this panel.", "mode": "no-view" },
    { "name": "toggle-hotbar", "title": "Toggle Hotbar", "description": "Show or hide the floating quick-action bar.", "mode": "no-view" },
    { "name": "toggle-cursor-highlights", "title": "Toggle Cursor Highlights", "description": "Cursor halo and click ripples for viewers.", "mode": "no-view" },
    { "name": "toggle-dimming", "title": "Toggle Dimming", "description": "Dim everything outside the region locally.", "mode": "no-view" }
  ],
  "dependencies": {
    "@raycast/api": "^1.88.4"
  },
  "devDependencies": {
    "@types/node": "^22.0.0",
    "@types/react": "^19.0.0",
    "react": "^19.0.0",
    "tsx": "^4.19.0",
    "typescript": "^5.7.0"
  },
  "scripts": {
    "dev": "ray develop",
    "build": "ray build -e dist",
    "test": "tsx --test tests/plist.test.ts",
    "typecheck": "tsc --noEmit"
  }
}
```

(All 12 commands declared up front; the three `view` commands get their files in Task 5 — `ray build` before then would fail on missing entry points, so Task 3 validates with `typecheck` only.)

`raycast/tsconfig.json`:

```json
{
  "compilerOptions": {
    "target": "ES2023",
    "lib": ["ES2023"],
    "module": "commonjs",
    "moduleResolution": "node",
    "jsx": "react-jsx",
    "strict": true,
    "esModuleInterop": true,
    "isolatedModules": true,
    "resolveJsonModule": true,
    "skipLibCheck": true
  },
  "include": ["src/**/*", "tests/**/*"]
}
```

Icon: `sips -z 512 512 Resources/AppIcon.png --out raycast/assets/icon.png`

- [ ] **Step 2: Shared helper**

`raycast/src/outcut.ts`:

```ts
import { open, showHUD } from "@raycast/api";

/** Fire an outcutshare:// deep link; the app is launched if not running.
 *  One-way by design — the app owns all failure UI beyond "not installed". */
export async function send(pathAndQuery: string, hud: string): Promise<void> {
  try {
    await open(`outcutshare://${pathAndQuery}`);
    await showHUD(hud);
  } catch {
    await showHUD("❌ Couldn't reach Outcut Share — is the app installed?");
  }
}
```

- [ ] **Step 3: The nine no-view commands**

Each file is a default async function calling `send`:

`raycast/src/share-last.ts`:

```ts
import { send } from "./outcut";

export default async function command() {
  await send("share-last", "Sharing last region");
}
```

The other eight, same shape with these `send` arguments:

| File | `send(path, hud)` |
| --- | --- |
| `select-region.ts` | `send("select", "Starting selection")` |
| `stop-sharing.ts` | `send("stop", "Stopped sharing")` |
| `toggle-pause.ts` | `send("pause", "Toggled pause")` |
| `toggle-recording.ts` | `send("record", "Toggled recording")` |
| `toggle-preview.ts` | `send("toggle?option=preview", "Toggled preview window")` |
| `toggle-hotbar.ts` | `send("toggle?option=hotbar", "Toggled hotbar")` |
| `toggle-cursor-highlights.ts` | `send("toggle?option=cursorHighlights", "Toggled cursor highlights")` |
| `toggle-dimming.ts` | `send("toggle?option=dimming", "Toggled dimming")` |

- [ ] **Step 4: Install and typecheck**

```bash
cd raycast && npm install && npm run typecheck
```

Expected: exit 0. Commit `package-lock.json` too.

- [ ] **Step 5: Commit**

```bash
git add raycast/package.json raycast/package-lock.json raycast/tsconfig.json raycast/.gitignore raycast/assets/icon.png raycast/src
git commit -m "feat: Raycast extension with direct share, stop, pause, record and presenter toggles"
```

---

### Task 4: Plist extraction for app state (TS, TDD)

**Files:**
- Create: `raycast/src/plist.ts`
- Test: `raycast/tests/plist.test.ts`

**Interfaces:**
- Produces: `extractStringKey(plist: string, key: string): string | null`; `parsePresets(plist: string): Preset[]`; `interface Preset { id: string; name: string; region: { x: number; y: number; width: number; height: number; displayID: number }; shareModeRaw: string }`.

- [ ] **Step 1: Write the failing test**

`raycast/tests/plist.test.ts`:

```ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { extractStringKey, parsePresets } from "../src/plist";

const SAMPLE_PRESETS = [
  {
    id: "AAAAAAAA-0000-0000-0000-000000000001",
    name: "Left Half",
    region: { x: 0, y: 100, width: 1280, height: 720, displayID: 3 },
    shareModeRaw: "hiddenWindow",
  },
];

// `defaults export` wraps base64 <data> at 68 chars with tab indentation —
// the extractor must tolerate embedded whitespace.
function wrap(b64: string): string {
  return b64.replace(/(.{60})/g, "$1\n\t");
}

function plistWith(entries: string): string {
  return `<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
${entries}
</dict>
</plist>`;
}

const FULL = plistWith(`	<key>followMode</key>
	<string>cursor</string>
	<key>presets</key>
	<data>
	${wrap(Buffer.from(JSON.stringify(SAMPLE_PRESETS)).toString("base64"))}
	</data>
	<key>shareMode</key>
	<string>virtualMonitor</string>`);

test("extractStringKey finds a top-level string", () => {
  assert.equal(extractStringKey(FULL, "followMode"), "cursor");
  assert.equal(extractStringKey(FULL, "shareMode"), "virtualMonitor");
});

test("extractStringKey returns null for absent keys", () => {
  assert.equal(extractStringKey(FULL, "missing"), null);
});

test("parsePresets round-trips despite base64 line wrapping", () => {
  const presets = parsePresets(FULL);
  assert.equal(presets.length, 1);
  assert.equal(presets[0].name, "Left Half");
  assert.equal(presets[0].id, "AAAAAAAA-0000-0000-0000-000000000001");
  assert.equal(presets[0].region.width, 1280);
});

test("parsePresets returns [] when the key is absent", () => {
  assert.deepEqual(parsePresets(plistWith("\t<key>other</key>\n\t<string>x</string>")), []);
});

test("parsePresets returns [] on malformed payloads", () => {
  const bad = plistWith("\t<key>presets</key>\n\t<data>!!!not-base64!!!</data>");
  assert.deepEqual(parsePresets(bad), []);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd raycast && npm test`
Expected: FAIL — cannot find `../src/plist`.

- [ ] **Step 3: Implement**

`raycast/src/plist.ts`:

```ts
/** Shape JSONEncoder writes for SettingsStore.presets (see Presets.swift). */
export interface Preset {
  id: string;
  name: string;
  region: { x: number; y: number; width: number; height: number; displayID: number };
  shareModeRaw: string;
}

function escapeRegExp(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

/** First match wins — fine here: the keys we read are unique, top-level
 *  keys of the exported com.outcutshare.app domain. */
function extractValue(plist: string, key: string, tag: "string" | "data"): string | null {
  const re = new RegExp(`<key>${escapeRegExp(key)}</key>\\s*<${tag}>([\\s\\S]*?)</${tag}>`);
  const match = plist.match(re);
  return match ? match[1] : null;
}

export function extractStringKey(plist: string, key: string): string | null {
  return extractValue(plist, key, "string");
}

export function parsePresets(plist: string): Preset[] {
  const raw = extractValue(plist, "presets", "data");
  if (!raw) return [];
  try {
    const decoded = JSON.parse(
      Buffer.from(raw.replace(/\s+/g, ""), "base64").toString("utf8"),
    );
    return Array.isArray(decoded) ? decoded : [];
  } catch {
    return [];
  }
}
```

(Note: `Buffer.from("!!!not-base64!!!", "base64")` silently skips invalid
chars, so that fixture decodes to garbage and fails at `JSON.parse` —
which is exactly the `[]` path being tested.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd raycast && npm test && npm run typecheck`
Expected: all pass, exit 0.

- [ ] **Step 5: Commit**

```bash
git add raycast/src/plist.ts raycast/tests/plist.test.ts
git commit -m "feat: read Outcut Share presets and modes from its defaults"
```

---

### Task 5: The three list commands (presets, follow mode, share mode)

**Files:**
- Create: `raycast/src/appState.ts`, `raycast/src/share-preset.tsx`, `raycast/src/set-follow-mode.tsx`, `raycast/src/set-share-mode.tsx`

**Interfaces:**
- Consumes: `send` (Task 3), `extractStringKey` / `parsePresets` / `Preset` (Task 4).
- Produces: `readAppState(): Promise<AppState>` with `interface AppState { presets: Preset[]; followMode: string; shareMode: string }`.

- [ ] **Step 1: App-state reader**

`raycast/src/appState.ts`:

```ts
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { extractStringKey, parsePresets, Preset } from "./plist";

const run = promisify(execFile);

export interface AppState {
  presets: Preset[];
  followMode: string;
  shareMode: string;
}

/** `defaults export` goes through cfprefsd, so values are never stale.
 *  Fallbacks mirror SettingsStore's init defaults. */
export async function readAppState(): Promise<AppState> {
  const { stdout } = await run(
    "/usr/bin/defaults",
    ["export", "com.outcutshare.app", "-"],
    { maxBuffer: 16 * 1024 * 1024 },
  );
  return {
    presets: parsePresets(stdout),
    followMode: extractStringKey(stdout, "followMode") ?? "off",
    shareMode: extractStringKey(stdout, "shareMode") ?? "virtualDisplay",
  };
}
```

- [ ] **Step 2: Share Preset list**

`raycast/src/share-preset.tsx`:

```tsx
import { Action, ActionPanel, Icon, List } from "@raycast/api";
import { useEffect, useState } from "react";
import { AppState, readAppState } from "./appState";
import { send } from "./outcut";

export default function SharePreset() {
  const [state, setState] = useState<AppState | null>(null);
  useEffect(() => {
    readAppState().then(setState, () =>
      setState({ presets: [], followMode: "off", shareMode: "virtualDisplay" }),
    );
  }, []);
  return (
    <List isLoading={state === null}>
      <List.EmptyView
        title="No presets saved yet"
        description="Save one from the Outcut Share menu: Presets → Save Current Region as Preset."
        icon={Icon.AppWindowGrid2x2}
      />
      {(state?.presets ?? []).map((preset) => (
        <List.Item
          key={preset.id}
          title={preset.name}
          subtitle={`${Math.round(preset.region.width)} × ${Math.round(preset.region.height)}`}
          icon={Icon.AppWindowGrid2x2}
          actions={
            <ActionPanel>
              <Action
                title="Share Preset"
                icon={Icon.Monitor}
                onAction={() =>
                  send(`preset?id=${encodeURIComponent(preset.id)}`, `Sharing “${preset.name}”`)
                }
              />
            </ActionPanel>
          }
        />
      ))}
    </List>
  );
}
```

- [ ] **Step 3: Set Follow Mode list**

`raycast/src/set-follow-mode.tsx`:

```tsx
import { Action, ActionPanel, Icon, List } from "@raycast/api";
import { useEffect, useState } from "react";
import { readAppState } from "./appState";
import { send } from "./outcut";

const MODES = [
  { value: "off", title: "Off", icon: Icon.CircleDisabled },
  { value: "activeWindow", title: "Active Window", icon: Icon.AppWindow },
  { value: "cursor", title: "Cursor", icon: Icon.Mouse },
];

export default function SetFollowMode() {
  const [current, setCurrent] = useState<string | null>(null);
  useEffect(() => {
    readAppState().then((s) => setCurrent(s.followMode), () => setCurrent("off"));
  }, []);
  return (
    <List isLoading={current === null}>
      {MODES.map((mode) => (
        <List.Item
          key={mode.value}
          title={mode.title}
          icon={mode.icon}
          accessories={current === mode.value ? [{ icon: Icon.Checkmark, tooltip: "Current" }] : []}
          actions={
            <ActionPanel>
              <Action
                title={`Follow: ${mode.title}`}
                icon={mode.icon}
                onAction={() => send(`follow?mode=${mode.value}`, `Follow: ${mode.title}`)}
              />
            </ActionPanel>
          }
        />
      ))}
    </List>
  );
}
```

- [ ] **Step 4: Set Share Mode list**

`raycast/src/set-share-mode.tsx`:

```tsx
import { Action, ActionPanel, Icon, List } from "@raycast/api";
import { useEffect, useState } from "react";
import { readAppState } from "./appState";
import { send } from "./outcut";

const MODES = [
  { value: "hiddenWindow", title: "Hidden Window", subtitle: "share window in the meeting app" },
  { value: "virtualDisplay", title: "Virtual Display", subtitle: "share screen in the meeting app" },
  { value: "virtualMonitor", title: "Virtual Monitor", subtitle: "private extra screen" },
];

export default function SetShareMode() {
  const [current, setCurrent] = useState<string | null>(null);
  useEffect(() => {
    readAppState().then((s) => setCurrent(s.shareMode), () => setCurrent("virtualDisplay"));
  }, []);
  return (
    <List isLoading={current === null}>
      <List.Section title="Share as" subtitle="applies while not sharing">
        {MODES.map((mode) => (
          <List.Item
            key={mode.value}
            title={mode.title}
            subtitle={mode.subtitle}
            icon={Icon.Monitor}
            accessories={current === mode.value ? [{ icon: Icon.Checkmark, tooltip: "Current" }] : []}
            actions={
              <ActionPanel>
                <Action
                  title={`Share as ${mode.title}`}
                  icon={Icon.Monitor}
                  onAction={() => send(`share-mode?mode=${mode.value}`, `Share as ${mode.title}`)}
                />
              </ActionPanel>
            }
          />
        ))}
      </List.Section>
    </List>
  );
}
```

- [ ] **Step 5: Validate**

```bash
cd raycast && npm run typecheck && npm test && npm run build
```

Expected: exit 0 for all three. (`ray build` needs the Raycast CLI only, not a running Raycast; if it unexpectedly requires login, `typecheck` + `test` are the gate and note it in the commit body.)

- [ ] **Step 6: Commit**

```bash
git add raycast/src/appState.ts raycast/src/share-preset.tsx raycast/src/set-follow-mode.tsx raycast/src/set-share-mode.tsx
git commit -m "feat: Raycast lists for presets, follow mode and share mode"
```

---

### Task 6: Docs

**Files:**
- Create: `docs/raycast.md`, `raycast/README.md`
- Modify: `README.md` ("What else it can do" list + docs table), `AGENTS.md` (layout section)

- [ ] **Step 1: Write `docs/raycast.md`**

Content requirements (write in the established docs voice — compare `docs/hotkeys.md`):
- **Setup**: install [Raycast](https://raycast.com) + Node ≥ 20; `cd raycast && npm install && npm run dev` — imports the extension into Raycast in development mode; it stays available after quitting the dev server (Ctrl-C); re-run `npm run dev` only to pick up extension code changes.
- **Commands**: the 12 commands with one-line descriptions (copy from package.json).
- **URL scheme**: table of every `outcutshare://` URL from the spec — the scheme works from any automation tool (`open "outcutshare://share-last"`), not just Raycast. Note the share-mode idle guard, the preset `id`/`name` fallback rules, and that pause/record are toggles that no-op while idle.
- **Caveats**: deep links go to whichever app copy LaunchServices registered last — launch the installed app once after moving it; the three list commands read the app's saved state, so they work even while the app is closed.

- [ ] **Step 2: Write `raycast/README.md`**

Three lines: what this folder is, `npm install && npm run dev` to load into Raycast, pointer to `../docs/raycast.md`.

- [ ] **Step 3: Link from README.md and AGENTS.md**

README "What else it can do" gains:

```markdown
- **Raycast extension** — trigger sharing, presets, pause, recording and
  modes from Raycast (or any tool, via `outcutshare://` deep links).
  → [raycast](docs/raycast.md)
```

README docs table gains: `| [Raycast & URL scheme](docs/raycast.md) | Extension setup, every outcutshare:// command |`

AGENTS.md layout block gains a `raycast/` line: `raycast/                    Raycast extension (TypeScript; URL-scheme client)`, and after the layout block add one sentence: URL-grammar changes touch `URLCommands.swift`, the `raycast/` commands, and `docs/raycast.md` together.

- [ ] **Step 4: Commit**

```bash
git add docs/raycast.md raycast/README.md README.md AGENTS.md
git commit -m "docs: Raycast extension and outcutshare:// URL scheme"
```

---

### Task 7: End-to-end with Raycast, merge, relaunch

- [ ] **Step 1: Full test + warning sweep**

```bash
swift test 2>&1 | tail -3
make app 2>&1 | grep -i warning    # expect no output
cd raycast && npm test && npm run typecheck
```

- [ ] **Step 2: Load the extension and walk it with the user**

```bash
pkill -x OutcutShare; open build/OutcutShare.app
cd raycast && npm run dev
```

`npm run dev` opens Raycast in development mode with the extension imported. Ask the user to run through: Share Last Region → Pause / Resume → Start / Stop Recording → Stop Sharing → Share Preset (their real presets listed) → Set Follow Mode / Set Share Mode (current values check-marked; mode switch while sharing shows the app's alert) → the four toggles. Fix anything they report before merging.

- [ ] **Step 3: Merge and relaunch**

```bash
git checkout main && git merge --no-ff feature/raycast-extension \
  -m "Merge feature/raycast-extension"
git push
make app && pkill -x OutcutShare; open build/OutcutShare.app
```

No release — polish collects until the user asks.
