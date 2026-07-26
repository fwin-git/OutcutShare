# RegionShare Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** macOS menu-bar app that drag-selects a screen region, exposes it as a virtual monitor (shareable in Zoom/Teams), and dims everything outside the region with configurable opacity.

**Architecture:** SPM executable package; ObjC target `CVirtualDisplay` declares the private `CGVirtualDisplay*` classes; Swift target `RegionShare` contains a `ShareSession` state machine that wires RegionSelector → VirtualDisplay → ScreenCaptureKit CaptureEngine → ProjectionWindow, plus a click-through DimOverlay. Makefile assembles `RegionShare.app`.

**Tech Stack:** Swift 6 toolchain in Swift 5 language mode, AppKit, SwiftUI (settings only), ScreenCaptureKit, private CoreGraphics `CGVirtualDisplay` API, XCTest.

## Global Constraints

- Platform: macOS 14+ (`platforms: [.macOS(.v14)]`), tested on macOS 26.5.
- `swiftLanguageMode(.v5)` on Swift targets (AppKit/SCStream delegate ergonomics).
- Bundle id `com.regionshare.app`, `LSUIElement = true`, ad-hoc codesign (`codesign -s -`).
- Private classes always resolved via `NSClassFromString`; nil → user-facing error, never crash.
- All user-facing state changes go through `ShareSession`; UI components never talk to each other directly.
- Commit after every task.

## File Structure

```
Package.swift
Makefile
README.md
Support/Info.plist
Sources/CVirtualDisplay/include/CVirtualDisplay.h   (private API declarations)
Sources/CVirtualDisplay/CVirtualDisplay.m           (empty; makes target buildable)
Sources/RegionShare/main.swift                      (app entry)
Sources/RegionShare/AppDelegate.swift
Sources/RegionShare/StatusBarController.swift
Sources/RegionShare/Geometry.swift                  (pure functions, unit-tested)
Sources/RegionShare/SettingsStore.swift             (unit-tested)
Sources/RegionShare/SettingsView.swift
Sources/RegionShare/RegionSelector.swift
Sources/RegionShare/VirtualDisplay.swift
Sources/RegionShare/CaptureEngine.swift
Sources/RegionShare/ProjectionWindow.swift
Sources/RegionShare/DimOverlay.swift
Sources/RegionShare/ShareSession.swift
Tests/RegionShareTests/GeometryTests.swift
Tests/RegionShareTests/SettingsStoreTests.swift
```

---

### Task 1: Package scaffold + Geometry (TDD)

**Files:**
- Create: `Package.swift`, `Sources/CVirtualDisplay/include/CVirtualDisplay.h`, `Sources/CVirtualDisplay/CVirtualDisplay.m`, `Sources/RegionShare/main.swift` (temporary print stub), `Sources/RegionShare/Geometry.swift`
- Test: `Tests/RegionShareTests/GeometryTests.swift`

**Interfaces (Produces):**
```swift
enum Geometry {
  static let minRegionSide: CGFloat = 64
  /// Rect from two drag points (any corner order).
  static func selectionRect(from a: CGPoint, to b: CGPoint) -> CGRect
  static func meetsMinimumSize(_ r: CGRect) -> Bool
  /// AppKit global rect (bottom-left origin) → display-local top-left-origin rect for SCStreamConfiguration.sourceRect.
  static func displayLocalTopLeftRect(appKitGlobal r: CGRect, screenFrame: CGRect) -> CGRect
  /// Capture pixel size = region points × source display scale, floored to even ints.
  static func capturePixelSize(region: CGRect, scale: CGFloat) -> (width: Int, height: Int)
}
```

- [ ] **Step 1:** Write `Package.swift`:

```swift
// swift-tools-version: 5.10
import PackageDescription
let package = Package(
  name: "RegionShare",
  platforms: [.macOS(.v14)],
  targets: [
    .target(name: "CVirtualDisplay"),
    .executableTarget(name: "RegionShare", dependencies: ["CVirtualDisplay"]),
    .testTarget(name: "RegionShareTests", dependencies: ["RegionShare"]),
  ]
)
```

`CVirtualDisplay.h` declares `CGVirtualDisplayDescriptor`, `CGVirtualDisplayMode`, `CGVirtualDisplaySettings`, `CGVirtualDisplay` exactly as in the validated probe (`scratchpad/probe/probe.m`). `CVirtualDisplay.m` contains only `#import "include/CVirtualDisplay.h"`. `main.swift` prints "RegionShare stub".

- [ ] **Step 2:** Write failing tests covering: corner order (all 4 drag directions produce the same normalized rect), min-size boundary (63 fails, 64 passes on each side), coordinate conversion (known screen frame `x:0,y:0,w:2560,h:1440`, region `x:100,y:200,w:800,h:600` → top-left-origin `x:100,y:640`; plus a secondary-screen offset case), pixel size (scale 2 doubles; odd results floored to even).
- [ ] **Step 3:** `swift test` → FAIL (missing symbols).
- [ ] **Step 4:** Implement `Geometry.swift`; conversion formula: `localX = r.minX - screenFrame.minX`, `localYTopLeft = screenFrame.maxY - r.maxY`.
- [ ] **Step 5:** `swift test` → PASS. Commit `feat: package scaffold and region geometry`.

### Task 2: SettingsStore (TDD)

**Files:**
- Create: `Sources/RegionShare/SettingsStore.swift`
- Test: `Tests/RegionShareTests/SettingsStoreTests.swift`

**Interfaces (Produces):**
```swift
final class SettingsStore: ObservableObject {
  static let shared = SettingsStore()
  init(defaults: UserDefaults = .standard)   // injectable for tests
  @Published var dimOpacity: Double          // 0.0...0.9, default 0.6
  @Published var dimmingEnabled: Bool        // default true
  @Published var showRegionBorder: Bool      // default true
  @Published var frameRate: Int              // 30 or 60, default 30
}
extern let settingsChangedNotification: Notification.Name  // posted on any change
```

- [ ] **Step 1:** Failing tests: fresh suite yields defaults (0.6/true/true/30); values persist through a second instance on the same suite; `dimOpacity` clamps to 0...0.9; setting a value posts `settingsChangedNotification`. Use `UserDefaults(suiteName: UUID().uuidString)` and remove the suite in `tearDown`.
- [ ] **Step 2:** `swift test` → FAIL.
- [ ] **Step 3:** Implement with `didSet` on each `@Published` writing to defaults + posting notification; read initial values in `init` (registering defaults first).
- [ ] **Step 4:** `swift test` → PASS. Commit `feat: settings store with persistence`.

### Task 3: App shell — status bar + settings window

**Files:**
- Create: `Sources/RegionShare/AppDelegate.swift`, `StatusBarController.swift`, `SettingsView.swift`
- Modify: `Sources/RegionShare/main.swift`

**Interfaces:**
- Consumes: `SettingsStore.shared`.
- Produces: `AppDelegate` holding `ShareSession` (stubbed until Task 8 as a protocol-free class with `startSelection()`, `stop()`, `var isActive: Bool`, `var onStateChange: (() -> Void)?`); `StatusBarController(session:)` builds the menu: *Select Region & Share*, *Stop Sharing* (enabled iff active), *Settings…*, *Quit RegionShare*.

- [ ] **Step 1:** `main.swift`: create `NSApplication.shared`, set `activationPolicy(.accessory)`, assign `AppDelegate`, `app.run()`. `SettingsView` is a SwiftUI `Form`: opacity `Slider` (0–90 %, percent label), dimming toggle, border toggle, frame-rate `Picker` (30/60); shown in a floating `NSWindow` via `NSHostingView` (created lazily, `isReleasedWhenClosed = false`, activates app when opened).
- [ ] **Step 2:** `swift build` → succeeds; `swift run` from terminal shows the status item with all four menu entries; Settings opens and sliders persist across relaunch. Commit `feat: menu bar app shell and settings UI`.

### Task 4: RegionSelector

**Files:**
- Create: `Sources/RegionShare/RegionSelector.swift`

**Interfaces:**
- Consumes: `Geometry.selectionRect`, `Geometry.meetsMinimumSize`.
- Produces:
```swift
struct SelectedRegion { let rect: CGRect /* AppKit global */; let screen: NSScreen
                        var displayID: CGDirectDisplayID }
final class RegionSelector {
  /// Shows a full-screen selection overlay on every screen. Calls back exactly once.
  func begin(completion: @escaping (SelectedRegion?) -> Void)
}
```

- [ ] **Step 1:** Implement: one borderless `NSWindow` per `NSScreen` at `.screenSaver` level, `backgroundColor: .clear`, hosting a `SelectionView` that fills with 25 % black, draws the live drag rect as a clear cutout (`NSCompositingOperation.clear` fill? — use even-odd path: fill whole bounds minus selection) plus 1 pt white stroke and a `W × H` size label; crosshair cursor via `resetCursorRects`. Windows `canBecomeKey`; Esc (`keyCode 53`) cancels → completion(nil). Mouse-up: convert view rect to AppKit global coordinates via `window.convertToScreen`, ignore if below minimum size, else completion with region + that window's screen. All windows close on completion; `NSApp.activate` on begin so key events arrive.
- [ ] **Step 2:** Manual test via a temporary "Select Region (log only)" wiring in the status menu: drag on screen prints the selected rect; Esc prints nil. Commit `feat: drag region selection overlay`.

### Task 5: VirtualDisplay wrapper

**Files:**
- Create: `Sources/RegionShare/VirtualDisplay.swift`

**Interfaces:**
- Consumes: `CVirtualDisplay` ObjC declarations.
- Produces:
```swift
final class VirtualDisplay {
  enum VDError: LocalizedError { case apiUnavailable, creationFailed, screenNeverAppeared }
  let displayID: CGDirectDisplayID
  /// Creates a display whose single mode is `sizeInPoints` (hiDPI when scale >= 2).
  init(sizeInPoints: CGSize, scale: CGFloat, name: String) throws
  /// Waits (async polling, 0.1 s steps, 5 s cap) for the matching NSScreen.
  func waitForScreen() async throws -> NSScreen
  func destroy()   // releases the CGVirtualDisplay → display goes offline
}
```

- [ ] **Step 1:** Implement mirroring the probe: descriptor (name, queue: main, sRGB primaries, `sizeInMillimeters` proportional to aspect at ~110 ppi, maxPixels = size × scale, vendor/product/serial constants), `CGVirtualDisplay(descriptor:)`, settings `hiDPI = scale >= 2 ? 1 : 0`, one `CGVirtualDisplayMode(width: Int(size.width), height: Int(size.height), refreshRate: 60)`. All four classes via `NSClassFromString`; any nil → `.apiUnavailable`. `waitForScreen` matches `NSScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]`.
- [ ] **Step 2:** Manual test: temporary menu hook creates a 1280×720 display for 10 s — verify it appears in System Settings → Displays, then disappears. Commit `feat: virtual display wrapper over private CGVirtualDisplay API`.

### Task 6: CaptureEngine + ProjectionWindow

**Files:**
- Create: `Sources/RegionShare/CaptureEngine.swift`, `Sources/RegionShare/ProjectionWindow.swift`

**Interfaces:**
- Consumes: `Geometry.displayLocalTopLeftRect`, `Geometry.capturePixelSize`, `SettingsStore.frameRate`.
- Produces:
```swift
final class CaptureEngine: NSObject, SCStreamOutput, SCStreamDelegate {
  enum CaptureError: LocalizedError { case permissionDenied, displayNotFound }
  var onFrame: ((IOSurface) -> Void)?
  var onStopped: ((Error?) -> Void)?
  func start(displayID: CGDirectDisplayID, sourceRectTopLeft: CGRect,
             pixelWidth: Int, pixelHeight: Int, fps: Int) async throws
  func stop() async
}
final class ProjectionWindow {
  init(screen: NSScreen)          // borderless window filling the virtual screen
  func display(surface: IOSurface) // layer.contents = surface inside CATransaction
  func close()
}
```

- [ ] **Step 1:** `CaptureEngine.start`: `SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)` (a TCC error maps to `.permissionDenied`); find `SCDisplay` by id; `SCContentFilter(display:excludingWindows:)` where excluded = windows whose `owningApplication?.processID == getpid()`; `SCStreamConfiguration`: `sourceRect`, `width/height` (pixels), `minimumFrameInterval = CMTime(value: 1, timescale: fps)`, `showsCursor = true`, `pixelFormat = kCVPixelFormatType_32BGRA`, `queueDepth = 5`; add stream output on a private serial queue; `startCapture`. Frame handler: `CMSampleBufferGetImageBuffer` → `CVPixelBufferGetIOSurface` → `onFrame`. Delegate `stream(_:didStopWithError:)` → `onStopped`.
- [ ] **Step 2:** `ProjectionWindow`: `NSWindow(contentRect: screen.frame, styleMask: .borderless, …)`, `level = .normal`, black layer-backed content view, `layer.contentsGravity = .resize`; `display(surface:)` sets `layer.contents` inside a `CATransaction` with actions disabled. `orderFrontRegardless()` on init.
- [ ] **Step 3:** Build passes (`swift build`). Runtime verification happens in Task 8 when the pieces are wired. Commit `feat: region capture engine and projection window`.

### Task 7: DimOverlay

**Files:**
- Create: `Sources/RegionShare/DimOverlay.swift`

**Interfaces:**
- Consumes: `SettingsStore` (`dimOpacity`, `dimmingEnabled`, `showRegionBorder`), `settingsChangedNotification`.
- Produces:
```swift
final class DimOverlay {
  /// region is in AppKit global coordinates; overlay covers `screen` only.
  init(region: CGRect, screen: NSScreen, settings: SettingsStore)
  func close()
}
```

- [ ] **Step 1:** Borderless window covering `screen.frame`, `level = .screenSaver`, `ignoresMouseEvents = true`, `backgroundColor = .clear`, `collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]`. View draws black at `dimOpacity` using an even-odd path (bounds + region-in-window-coords) so the region stays fully clear; when `showRegionBorder`, strokes a 2 pt accent (`NSColor.controlAccentColor`) rectangle *outside* the region edge (inset by −1 pt) so no stroke pixel lies inside the captured area. Observes `settingsChangedNotification` → `needsDisplay`; when `dimmingEnabled` is false draws only the border.
- [ ] **Step 2:** Build passes. Visual check in Task 8. Commit `feat: dim overlay with region cutout`.

### Task 8: ShareSession orchestration

**Files:**
- Create: `Sources/RegionShare/ShareSession.swift`
- Modify: `AppDelegate.swift`, `StatusBarController.swift` (replace stub/manual hooks)

**Interfaces:**
- Consumes: everything above, exact signatures as declared.
- Produces:
```swift
@MainActor final class ShareSession {
  private(set) var state: State  // enum State { case idle, selecting, active }
  var onStateChange: (() -> Void)?
  func startSelection()   // idle → selecting → active (or back to idle on cancel/error)
  func stop()             // any → idle; always safe
}
```

- [ ] **Step 1:** `startSelection`: `RegionSelector.begin` → on region: `Task { }`: create `VirtualDisplay(sizeInPoints: region.size, scale: screen.backingScaleFactor, name: "Region Share")`, `waitForScreen()`, `ProjectionWindow(screen:)`, compute `sourceRect = Geometry.displayLocalTopLeftRect(...)` and pixel size, `CaptureEngine.start(...)` with `onFrame → projection.display`, then `DimOverlay`. Any thrown error → tear down whatever exists, `NSAlert` with `localizedDescription`; `.permissionDenied` alert gains an "Open System Settings" button → `open x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture` (also call `CGRequestScreenCaptureAccess()` once beforehand when `CGPreflightScreenCaptureAccess()` is false). `onStopped` (stream died) and frame-rate settings change → restart or stop via main actor. `stop()` tears down in order capture → overlay → projection → virtual display. `applicationWillTerminate` calls `stop()`.
- [ ] **Step 2:** Full manual pass: select region → virtual display appears; Displays settings lists "Region Share"; region content mirrors live onto it (check via Displays arrangement or Zoom preview); outside dimmed; opacity slider live-updates; stop restores everything; re-select works twice in a row. Commit `feat: share session orchestration`.

### Task 9: App bundle, Makefile, README, smoke test

**Files:**
- Create: `Makefile`, `Support/Info.plist`, `README.md`, `.gitignore`

**Interfaces:**
- Produces: `make app` → `build/RegionShare.app`; `make run`; `make test`.

- [ ] **Step 1:** `Support/Info.plist`: `CFBundleIdentifier com.regionshare.app`, `CFBundleName RegionShare`, `CFBundleExecutable RegionShare`, `LSUIElement true`, `LSMinimumSystemVersion 14.0`, `NSHighResolutionCapable true`, `CFBundlePackageType APPL`, version 1.0.
- [ ] **Step 2:** `Makefile`: `swift build -c release --arch arm64`; assemble `build/RegionShare.app/Contents/{MacOS,Resources}`; copy binary + plist; `codesign --force -s - build/RegionShare.app`. Targets: `app` (default), `test` (`swift test`), `run` (`open build/RegionShare.app`), `clean`.
- [ ] **Step 3:** Smoke test: `make app && open build/RegionShare.app`, then `pgrep -x RegionShare` after 3 s → running; quit via menu. `swift test` green.
- [ ] **Step 4:** `README.md`: what it does, build (`make app`), first-run Screen Recording permission walkthrough, how to pick "Region Share"/"Desktop 2" in Zoom & Teams, settings reference, private-API caveat, mouse-can-enter-virtual-display caveat.
- [ ] **Step 5:** Commit `feat: app bundle, build tooling, docs`.

## Self-Review

- Spec coverage: selection (T4), virtual monitor (T5), capture/projection (T6), dimming + configurability (T2/T3/T7), orchestration/error handling (T8), permission flow (T8), bundle/persistent TCC (T9). ✔
- No placeholders; signatures consistent across tasks (`SelectedRegion`, `Geometry.*`, `SettingsStore` names match). ✔
- Single subsystem, one plan. ✔
