import AppKit

/// Owns the lifecycle of one sharing session: selection, virtual display,
/// capture, projection and dimming.
@MainActor
final class ShareSession {
    enum State { case idle, selecting, active }

    private(set) var state: State = .idle {
        didSet { notifyUI() }
    }

    private func notifyUI() {
        onStateChange?()
        hotbar.refresh()
        preview.refresh()
        NotificationCenter.default.post(name: sessionStateChangedNotification, object: self)
    }
    var onStateChange: (() -> Void)?
    /// Read from the capture sample queue to gate frame forwarding.
    private(set) nonisolated(unsafe) var isPaused = false
    /// Set by the app delegate: opens the guided permissions window. Called
    /// instead of firing raw system prompts when the permission is missing.
    var onPermissionsNeeded: (() -> Void)?
    var isActive: Bool { state == .active }

    private nonisolated(unsafe) let settings: SettingsStore
    private var selector: RegionSelector?
    private var virtualDisplay: VirtualDisplay?
    private var capture: CaptureEngine?
    private var output: LiveFrameWindow?
    private var overlay: DimOverlay?
    private var currentRegion: SelectedRegion?
    private var activeFrameRate = 0
    private var activeShareMode: ShareMode = .virtualDisplay
    private var activeCrisp = false
    private var activeExclusions: [String] = []
    private var settingsObserver: NSObjectProtocol?
    private var mover: RegionMover?
    private var moveBackupRect: CGRect?
    private var activeAspect: CGFloat?
    private var activeOutputPixelSize: (width: Int, height: Int) = (0, 0)
    private var pendingCaptureUpdate: (rect: CGRect, pixelWidth: Int?, pixelHeight: Int?)?
    private var captureUpdateInFlight = false

    nonisolated init(settings: SettingsStore = .shared) {
        self.settings = settings
    }

    func startSelection() {
        guard state == .idle else { return }
        guard CGPreflightScreenCaptureAccess() else {
            onPermissionsNeeded?()
            return
        }
        state = .selecting
        let selector = RegionSelector()
        self.selector = selector
        selector.begin { [weak self] region in
            guard let self else { return }
            self.selector = nil
            guard let region else {
                self.state = .idle
                return
            }
            Task { await self.activate(region: region) }
        }
    }

    /// Programmatic entry used by the --share-test debug mode.
    func startSharing(rect: CGRect, on screen: NSScreen) {
        guard state == .idle else { return }
        state = .selecting
        Task { await activate(region: SelectedRegion(rect: rect, screen: screen)) }
    }

    /// One-keystroke re-share of the most recent region.
    func shareLastRegion() {
        guard state == .idle, let stored = settings.lastRegion else { return }
        startStored(region: stored)
    }

    /// Shares a preset; if a session is active it is replaced.
    func sharePreset(_ preset: RegionPreset) {
        if state != .idle {
            teardown()
            state = .idle
        }
        if let mode = ShareMode(rawValue: preset.shareModeRaw), mode != settings.shareMode {
            settings.shareMode = mode
        }
        startStored(region: preset.region)
    }

    func saveCurrentRegionAsPreset(named name: String) {
        guard let region = currentRegion else { return }
        settings.presets.append(RegionPreset(
            name: name,
            region: StoredRegion(rect: region.rect, displayID: region.displayID),
            shareModeRaw: activeShareMode.rawValue))
    }

    private func startStored(region stored: StoredRegion) {
        let screens = NSScreen.screens
        guard let resolved = RegionResolver.resolve(
            rect: stored.rect, displayID: stored.displayID,
            screens: screens.map { ($0.displayID, $0.frame) }) else { return }
        state = .selecting
        let screen = screens[resolved.screenIndex]
        Task { await activate(region: SelectedRegion(rect: resolved.rect, screen: screen)) }
    }

    /// Starts/stops recording the region to an .mp4 in the recording folder.
    func toggleRecording() {
        guard state == .active else { return }
        if let recorder {
            self.recorder = nil
            capture?.onSampleBuffer = nil
            Task {
                if let url = await recorder.stop() {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                self.notifyUI()
            }
            return
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let url = settings.recordingFolderURL
            .appendingPathComponent("Recording \(formatter.string(from: Date())).mp4")
        let recorder = RecordingEngine()
        do {
            try recorder.start(pixelWidth: activeOutputPixelSize.width,
                               pixelHeight: activeOutputPixelSize.height, to: url)
        } catch {
            presentError(error, title: "Recording couldn't start")
            return
        }
        self.recorder = recorder
        capture?.onSampleBuffer = { [weak self] sample in
            // Respect privacy pause: no raw frames reach the file while paused.
            guard let self, !self.isPaused else { return }
            recorder.append(sample)
        }
        notifyUI()
    }

    /// Pauses/resumes what viewers see without touching the stream: frames
    /// stop being forwarded; the privacy style optionally covers the output.
    func togglePause() {
        guard state == .active else { return }
        isPaused.toggle()
        if isPaused && settings.pauseStyle == .privacyScreen {
            output?.showPrivacyScreen()
            preview.showPrivacyScreen()
        } else {
            output?.hidePrivacyScreen()
            preview.hidePrivacyScreen()
        }
        notifyUI()
    }

    func stop() {
        guard state != .idle else { return }
        if let region = currentRegion {
            // Keep the final (possibly moved/resized) rect for re-sharing.
            settings.lastRegion = StoredRegion(rect: region.rect, displayID: region.displayID)
        }
        teardown()
        state = .idle
    }

    /// Frames received by the active capture stream (debug/testing aid).
    var receivedFrameCount: Int { capture?.frameCount ?? 0 }

    var currentRegionRect: CGRect? { currentRegion?.rect }
    var currentScreen: NSScreen? { currentRegion?.screen }
    var currentAspect: CGFloat? { activeAspect }

    private lazy var follow = FollowController(session: self, settings: settings)
    private lazy var cursorEmphasis = CursorEmphasisController(session: self, settings: settings)
    private lazy var hotbar = HotbarController(session: self, settings: settings)
    private var lastHotbarEnabled = true
    private lazy var preview = PreviewWindowController(session: self, settings: settings)
    private var lastPreviewEnabled = false
    private var recorder: RecordingEngine?
    var isRecording: Bool { recorder?.isRecording ?? false }
    var followMode: FollowMode { follow.mode }

    /// Menu/hotbar entry point — persists the choice; the active session
    /// applies it via the settings observer.
    func setFollow(mode: FollowMode) {
        settings.followMode = mode
        notifyUI()
    }

    /// Enters interactive adjust mode: drag the region to move it, drag its
    /// corners to resize (aspect-locked in virtual-display mode), arrow keys
    /// nudge, Esc reverts.
    func startAdjust() {
        guard state == .active, let region = currentRegion, mover == nil else { return }
        moveBackupRect = region.rect
        let mover = RegionMover()
        self.mover = mover
        mover.begin(region: region.rect, screen: region.screen,
                    aspect: activeAspect) { [weak self] rect in
            self?.setRegionRect(rect)
        } onEnd: { [weak self] cancelled in
            guard let self else { return }
            if cancelled, let backup = self.moveBackupRect {
                self.setRegionRect(backup)
            }
            self.moveBackupRect = nil
            self.mover = nil
        }
    }

    /// Moves the active region (same size) to a new origin, clamped to its
    /// screen (debug/testing entry).
    func moveRegion(to proposedOrigin: CGPoint) {
        guard let region = currentRegion else { return }
        let origin = Geometry.clampedRegionOrigin(proposedOrigin,
                                                  regionSize: region.rect.size,
                                                  screenFrame: region.screen.frame)
        setRegionRect(CGRect(origin: origin, size: region.rect.size))
    }

    /// Grows/shrinks the region from its bottom-left corner, honoring the
    /// mode's aspect constraint (debug/testing entry).
    func resizeRegion(byWidth dw: CGFloat, height dh: CGFloat) {
        guard let region = currentRegion else { return }
        let r = region.rect
        setRegionRect(Geometry.resizedRegion(anchor: r.origin,
                                             dragged: CGPoint(x: r.maxX + dw, y: r.maxY + dh),
                                             aspect: activeAspect,
                                             screenFrame: region.screen.frame))
    }

    /// Applies a moved and/or resized region to the live session: dim overlay
    /// follows immediately; the capture stream is re-pointed on the fly. On
    /// resize, hidden-window mode also resizes the mirror window and the
    /// capture output, while virtual-display mode keeps its display
    /// resolution and scales the (aspect-identical) region into it.
    func setRegionRect(_ rect: CGRect) {
        guard state == .active, let region = currentRegion, rect != region.rect else { return }
        let sizeChanged = rect.size != region.rect.size
        currentRegion = SelectedRegion(rect: rect, screen: region.screen)
        overlay?.update(region: rect)
        hotbar.regionChanged(rect)
        if sizeChanged {
            preview.aspectChanged(rect.width / rect.height)
        }
        var pixelSize: (width: Int, height: Int)? = nil
        if sizeChanged && activeShareMode == .hiddenWindow {
            output?.resize(to: Geometry.hiddenWindowFrame(regionSize: rect.size,
                                                          screenFrame: region.screen.frame))
            pixelSize = Geometry.capturePixelSize(region: rect,
                                                  scale: region.screen.backingScaleFactor)
            activeOutputPixelSize = pixelSize!
        }
        scheduleCaptureUpdate(rect, screen: region.screen, pixelSize: pixelSize)
    }

    /// Coalesces rapid drag updates: at most one updateConfiguration call is
    /// in flight; the newest pending update wins.
    private func scheduleCaptureUpdate(_ rect: CGRect, screen: NSScreen,
                                       pixelSize: (width: Int, height: Int)?) {
        let local = Geometry.displayLocalTopLeftRect(appKitGlobal: rect,
                                                     screenFrame: screen.frame)
        pendingCaptureUpdate = (local, pixelSize?.width, pixelSize?.height)
        guard !captureUpdateInFlight else { return }
        captureUpdateInFlight = true
        Task {
            while let next = pendingCaptureUpdate {
                pendingCaptureUpdate = nil
                guard let capture else { break }
                try? await capture.updateCapture(sourceRectTopLeft: next.rect,
                                                 pixelWidth: next.pixelWidth,
                                                 pixelHeight: next.pixelHeight)
            }
            captureUpdateInFlight = false
        }
    }

    private func activate(region: SelectedRegion) async {
        do {
            let mode = settings.shareMode
            let sourceScale = region.screen.backingScaleFactor
            let output: LiveFrameWindow
            switch mode {
            case .virtualDisplay:
                let vd = try VirtualDisplay(sizeInPoints: region.rect.size,
                                            scale: sourceScale, name: "Outcut Share",
                                            forceHiDPI: settings.crispOutput)
                virtualDisplay = vd
                let virtualScreen = try await vd.waitForScreen()
                output = LiveFrameWindow(contentRect: virtualScreen.frame, level: .screenSaver)
            case .hiddenWindow:
                let frame = Geometry.hiddenWindowFrame(regionSize: region.rect.size,
                                                       screenFrame: region.screen.frame)
                output = LiveFrameWindow(contentRect: frame, level: .normal,
                                         title: settings.effectiveShareWindowTitle)
            }
            self.output = output
            // Created before the capture filter snapshots the window list so
            // overlay, mirror window and hotbar are excluded from capture.
            overlay = DimOverlay(region: region.rect, screen: region.screen, settings: settings)
            lastHotbarEnabled = settings.hotbarEnabled
            if settings.hotbarEnabled {
                hotbar.show(region: region.rect, screen: region.screen)
            }
            lastPreviewEnabled = settings.previewWindowEnabled
            if settings.previewWindowEnabled {
                preview.show(region: region.rect, screen: region.screen)
            }

            let capture = CaptureEngine()
            self.capture = capture
            // The preview always receives frames (even while hidden) so it
            // shows a current picture the instant it's enabled mid-session.
            let preview = self.preview
            capture.onFrame = { [weak self, weak output, weak preview] surface in
                guard self?.isPaused != true else { return }
                output?.display(surface: surface)
                preview?.display(surface: surface)
            }
            capture.onStopped = { [weak self] error in
                Task { @MainActor in self?.handleStreamStopped(error) }
            }
            let sourceRect = Geometry.displayLocalTopLeftRect(appKitGlobal: region.rect,
                                                             screenFrame: region.screen.frame)
            let (pw, ph) = Geometry.capturePixelSize(region: region.rect, scale: sourceScale)
            activeExclusions = settings.excludedBundleIDs
            try await capture.start(displayID: region.displayID, sourceRectTopLeft: sourceRect,
                                    pixelWidth: pw, pixelHeight: ph, fps: settings.frameRate,
                                    excludedBundleIDs: activeExclusions)

            currentRegion = region
            activeFrameRate = settings.frameRate
            activeShareMode = mode
            activeCrisp = settings.crispOutput
            activeAspect = mode == .virtualDisplay
                ? region.rect.width / region.rect.height : nil
            activeOutputPixelSize = (pw, ph)
            observeSettingsChanges()
            state = .active
            if settings.followMode != .off {
                follow.set(mode: settings.followMode)
            }
            cursorEmphasis.start(output: output)
            settings.lastRegion = StoredRegion(rect: region.rect, displayID: region.displayID)
        } catch {
            teardown()
            state = .idle
            presentError(error)
        }
    }

    private func observeSettingsChanges() {
        guard settingsObserver == nil else { return }
        settingsObserver = NotificationCenter.default.addObserver(
            forName: settingsChangedNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.settingsDidChange()
            }
        }
    }

    private func settingsDidChange() {
        guard state == .active else { return }
        if settings.shareMode != activeShareMode
            || (activeShareMode == .virtualDisplay && settings.crispOutput != activeCrisp) {
            restartSession()
        } else {
            frameRateChangedIfNeeded()
            cursorEmphasis.settingsChanged()
            if activeShareMode == .hiddenWindow {
                output?.setTitle(settings.effectiveShareWindowTitle)
            }
            if settings.excludedBundleIDs != activeExclusions, let capture {
                activeExclusions = settings.excludedBundleIDs
                let exclusions = activeExclusions
                Task { try? await capture.updateExclusions(exclusions) }
            }
            if follow.mode != settings.followMode {
                follow.set(mode: settings.followMode)
            }
            if settings.hotbarEnabled != lastHotbarEnabled {
                lastHotbarEnabled = settings.hotbarEnabled
                if settings.hotbarEnabled {
                    if let region = currentRegion {
                        hotbar.show(region: region.rect, screen: region.screen)
                    }
                } else {
                    hotbar.close()
                }
            }
            if settings.previewWindowEnabled != lastPreviewEnabled {
                lastPreviewEnabled = settings.previewWindowEnabled
                if settings.previewWindowEnabled {
                    if let region = currentRegion {
                        preview.show(region: region.rect, screen: region.screen)
                    }
                } else {
                    preview.close()
                }
            }
            hotbar.refresh()
        }
    }

    /// Mode switches need the whole output pipeline rebuilt; the region is kept.
    private func restartSession() {
        guard let region = currentRegion else { return }
        teardown()
        state = .selecting
        Task { await activate(region: region) }
    }

    private func frameRateChangedIfNeeded() {
        guard state == .active, settings.frameRate != activeFrameRate,
              let region = currentRegion, let capture else { return }
        activeFrameRate = settings.frameRate
        let fps = activeFrameRate
        let (pw, ph) = activeOutputPixelSize
        Task {
            await capture.stop()
            let sourceRect = Geometry.displayLocalTopLeftRect(appKitGlobal: region.rect,
                                                             screenFrame: region.screen.frame)
            do {
                try await capture.start(displayID: region.displayID, sourceRectTopLeft: sourceRect,
                                        pixelWidth: pw, pixelHeight: ph, fps: fps,
                                        excludedBundleIDs: activeExclusions)
            } catch {
                handleStreamStopped(error)
            }
        }
    }

    private func handleStreamStopped(_ error: Error?) {
        guard state == .active else { return }
        teardown()
        state = .idle
        if let error {
            presentError(error, title: "Sharing stopped")
        }
    }

    private func teardown() {
        isPaused = false
        follow.set(mode: .off)
        hotbar.close()
        preview.close()
        cursorEmphasis.stop()
        if let recorder {
            self.recorder = nil
            capture?.onSampleBuffer = nil
            Task {
                if let url = await recorder.stop() {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
        }
        mover?.close()
        mover = nil
        moveBackupRect = nil
        pendingCaptureUpdate = nil
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
            self.settingsObserver = nil
        }
        if let capture {
            capture.onStopped = nil
            capture.onFrame = nil
            Task { await capture.stop() }
        }
        capture = nil
        overlay?.close()
        overlay = nil
        output?.close()
        output = nil
        virtualDisplay?.destroy()
        virtualDisplay = nil
        currentRegion = nil
    }

    private func presentError(_ error: Error, title: String = "OutcutShare couldn't start sharing") {
        if case CaptureEngine.CaptureError.permissionDenied = error {
            onPermissionsNeeded?()
            return
        }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        NSApp.activate(ignoringOtherApps: true)
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
