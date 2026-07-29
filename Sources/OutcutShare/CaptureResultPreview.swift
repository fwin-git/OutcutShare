import AppKit
import AVFoundation
import Quartz
import SwiftUI

@MainActor
final class CaptureResultModel: ObservableObject {
    @Published var image: NSImage?
    @Published var isVideo = false
    @Published var pill: String?
    /// Card size is dictated by the controller — the view pins itself to it
    /// so the hosting view can never inflate the panel to the image's
    /// native size (which pushed the corner buttons out of frame).
    @Published var cardSize = CGSize(width: 280, height: 160)
    // Trim mode (recordings only).
    @Published var trimming = false
    @Published var exporting = false
    @Published var trimIn: Double = 0
    @Published var trimOut: Double = 1
    @Published var thumbnails: [NSImage] = []
    /// Frame at the handle being dragged; replaces the poster while set.
    @Published var scrubImage: NSImage?
    @Published var duration: Double = 0
    /// Copy-chip feedback: shows a checkmark for a moment after copying.
    @Published var copied = false

    @Published var ocrState: OCRChipState = .idle
}

/// Countdown fraction on its own tiny observable: only the ring view
/// observes it, so 30 Hz updates don't re-render (and leak observation
/// registrations for) the whole card — see the macOS 26 note in AGENTS.md.
@MainActor
final class CaptureResultRing: ObservableObject {
    @Published var fraction: Double = 1
}

struct CaptureResultActions {
    var copyFile: () -> Void
    var copyText: () -> Void
    var dragURL: () -> URL?
    var dragThumbnail: () -> NSImage?
    var dragActive: (Bool) -> Void
    var revealInFinder: () -> Void
    var quickLook: () -> Void
    var beginTrim: () -> Void
    var applyTrim: () -> Void
    var cancelTrim: () -> Void
    /// Handle drag position for the frame preview; nil = drag ended.
    var scrub: (Double?) -> Void
    var trash: () -> Void
    var hoverChanged: (Bool) -> Void
    /// Demo runs only: resolved card-item rects (hosting-view coordinates).
    var reportItemBounds: ([String: CGRect]) -> Void = { _ in }
}

/// The card that folds out under the hotbar after a capture: the shot (or
/// the recording's poster), corner chips styled like the shared-output
/// preview's pause button, a countdown ring and a duration/size pill.
/// The scissors chip morphs it into a drag-to-trim editor.
/// Card-item bounds keyed by chip help string (plus "__image__" for the
/// drag-out surface and "__timeline__" for the trim strip) — demo
/// choreography resolves these to click real chips.
private struct CardItemBounds: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>],
                       nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

struct CaptureResultView: View {
    static let timelineHeight: CGFloat = 74

    @ObservedObject var model: CaptureResultModel
    @ObservedObject var ring: CaptureResultRing
    let actions: CaptureResultActions

    var body: some View {
        VStack(spacing: 8) {
            imageArea
            if model.trimming {
                TrimTimeline(model: model, scrub: actions.scrub)
                    .frame(height: Self.timelineHeight)
                    .anchorPreference(key: CardItemBounds.self, value: .bounds) {
                        ["__timeline__": $0]
                    }
            }
        }
        .frame(width: model.cardSize.width, height: model.cardSize.height)
        .onHover { actions.hoverChanged($0) }
        .overlayPreferenceValue(CardItemBounds.self) { anchors in
            GeometryReader { geo in
                Color.clear
                    .onChange(of: anchors.mapValues { geo[$0] }, initial: true) { _, rects in
                        if DemoState.active { actions.reportItemBounds(rects) }
                    }
            }
            .allowsHitTesting(false)
        }
    }

    private var imageHeight: CGFloat {
        model.cardSize.height - (model.trimming ? Self.timelineHeight + 8 : 0)
    }

    private var imageArea: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image = model.scrubImage ?? model.image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.black.opacity(0.4)
                }
            }
            // Explicit size: scaledToFill reports its overflowing fill size,
            // which would inflate the ZStack (and push every overlay out of
            // the visible panel) if this only capped at maxWidth/maxHeight.
            .frame(width: model.cardSize.width, height: imageHeight)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.white.opacity(0.25)))
            // The picture itself is a drag source too — straight into
            // Finder, Slack, mails … (hover is forwarded so the countdown
            // still pauses while the cursor is on the card).
            .overlay(FileDragArea(url: actions.dragURL,
                                  thumbnail: actions.dragThumbnail,
                                  onHover: actions.hoverChanged,
                                  dragActive: actions.dragActive))
            .anchorPreference(key: CardItemBounds.self, value: .bounds) {
                ["__image__": $0]
            }

            HStack(spacing: 6) {
                if model.trimming {
                    if model.exporting {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 30, height: 30)
                            .background(Color.black.opacity(0.55), in: Circle())
                    } else {
                        chip("checkmark", help: "Save trimmed copy",
                             action: actions.applyTrim)
                    }
                    chip("xmark", help: "Cancel trim", action: actions.cancelTrim)
                } else {
                    chip(model.copied ? "checkmark" : "doc.on.doc",
                         help: "Copy file — or drag it out",
                         action: actions.copyFile)
                        .overlay(FileDragArea(url: actions.dragURL,
                                              thumbnail: actions.dragThumbnail,
                                              onClick: actions.copyFile,
                                              dragActive: actions.dragActive))
                    chip("folder", help: "Show in Finder", action: actions.revealInFinder)
                    chip("eye", help: model.isVideo ? "Preview with playback" : "Preview large",
                         action: actions.quickLook)
                    if model.ocrState == .working {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 30, height: 30)
                            .background(Color.black.opacity(0.55), in: Circle())
                    } else {
                        chip(ocrSymbol, help: "Copy text (OCR)", action: actions.copyText)
                    }
                    if model.isVideo {
                        chip("scissors", help: "Trim recording", action: actions.beginTrim)
                    }
                    chip("trash", help: "Delete file", action: actions.trash)
                }
            }
            .padding(6)

            if !model.trimming {
                ringView
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: .topLeading)
            }

            if let pill = model.pill, !model.trimming {
                Text(pill)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.72), in: Capsule())
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: .bottomTrailing)
            }
        }
    }

    private var ocrSymbol: String {
        switch model.ocrState {
        case .done: return "checkmark"
        case .empty: return "questionmark"
        default: return "text.viewfinder"
        }
    }

    private var ringView: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.25), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: ring.fraction)
                .stroke(.white.opacity(0.9),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 16, height: 16)
        .padding(4)
        .background(Color.black.opacity(0.4), in: Circle())
    }

    private func chip(_ symbol: String, help: String,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Color.black.opacity(0.55), in: Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .anchorPreference(key: CardItemBounds.self, value: .bounds) { [help: $0] }
    }
}

/// AppKit-level file drag source: SwiftUI's onDrag preview is ignored on
/// macOS, so the ghost is drawn via NSDraggingItem — full control over the
/// proxy image and its size, plus real drag begin/end callbacks.
struct FileDragArea: NSViewRepresentable {
    var url: () -> URL?
    var thumbnail: () -> NSImage?
    var onClick: (() -> Void)?
    var onHover: ((Bool) -> Void)?
    var dragActive: (Bool) -> Void

    func makeNSView(context: Context) -> FileDragNSView {
        let view = FileDragNSView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: FileDragNSView, context: Context) {
        view.fileURL = url
        view.thumbnailProvider = thumbnail
        view.onClick = onClick
        view.onHoverChanged = onHover
        view.onDragStateChanged = dragActive
    }
}

final class FileDragNSView: NSView, NSDraggingSource {
    var fileURL: (() -> URL?)?
    var thumbnailProvider: (() -> NSImage?)?
    var onClick: (() -> Void)?
    var onHoverChanged: ((Bool) -> Void)?
    var onDragStateChanged: ((Bool) -> Void)?
    private var mouseDownEvent: NSEvent?
    private var didDrag = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { onHoverChanged?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChanged?(false) }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !didDrag, let down = mouseDownEvent, let url = fileURL?() else { return }
        let dx = event.locationInWindow.x - down.locationInWindow.x
        let dy = event.locationInWindow.y - down.locationInWindow.y
        guard dx * dx + dy * dy > 16 else { return }
        didDrag = true
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        let thumb = thumbnailProvider?()
        let size = thumb?.size ?? CGSize(width: 64, height: 64)
        let origin = convert(down.locationInWindow, from: nil)
        item.setDraggingFrame(CGRect(x: origin.x - size.width / 2,
                                     y: origin.y - size.height / 2,
                                     width: size.width, height: size.height),
                              contents: thumb)
        beginDraggingSession(with: [item], event: down, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        if !didDrag { onClick?() }
        mouseDownEvent = nil
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        onDragStateChanged?(true)
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint,
                         operation: NSDragOperation) {
        onDragStateChanged?(false)
    }
}

/// Filmstrip with two draggable handles; the range between them is what
/// "Save trimmed copy" keeps. Dragging a handle scrubs the big preview.
struct TrimTimeline: View {
    @ObservedObject var model: CaptureResultModel
    let scrub: (Double?) -> Void
    @State private var draggingOutHandle: Bool?

    private static let stripHeight: CGFloat = 40

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    filmstrip(width: width)
                    // Dim the discarded ranges.
                    Rectangle()
                        .fill(.black.opacity(0.6))
                        .frame(width: max(0, width * model.trimIn))
                    Rectangle()
                        .fill(.black.opacity(0.6))
                        .frame(width: max(0, width * (1 - model.trimOut)))
                        .offset(x: width * model.trimOut)
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                        .frame(width: max(4, width * (model.trimOut - model.trimIn)))
                        .offset(x: width * model.trimIn)
                    handle(at: model.trimIn, width: width)
                    handle(at: model.trimOut, width: width)
                }
                .contentShape(Rectangle())
                // One gesture for the whole strip: it grabs whichever handle
                // is closer at press time, so there's no fiddly hit target.
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let fraction = min(1, max(0, Double(value.location.x)
                                                        / Double(width)))
                            if draggingOutHandle == nil {
                                draggingOutHandle = abs(fraction - model.trimOut)
                                    < abs(fraction - model.trimIn)
                            }
                            let minGap = model.duration > 0
                                ? min(0.5, 0.5 / model.duration) : 0.05
                            if draggingOutHandle == true {
                                model.trimOut = TrimMath.clampedOut(
                                    fraction, in: model.trimIn, minGap: minGap)
                                scrub(model.trimOut)
                            } else {
                                model.trimIn = TrimMath.clampedIn(
                                    fraction, out: model.trimOut, minGap: minGap)
                                scrub(model.trimIn)
                            }
                        }
                        .onEnded { _ in
                            draggingOutHandle = nil
                            scrub(nil)
                        }
                )
            }
            .frame(height: Self.stripHeight)
            HStack {
                Text(TrimMath.timeString(model.trimIn * model.duration))
                Spacer()
                Text("keeps \(TrimMath.timeString((model.trimOut - model.trimIn) * model.duration))")
                Spacer()
                Text(TrimMath.timeString(model.trimOut * model.duration))
            }
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 2)
        }
        // Own dark backing: the panel behind is transparent, and the labels
        // must stay readable over any desktop content.
        .padding(6)
        .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
    }

    private func filmstrip(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            if model.thumbnails.isEmpty {
                Color.black.opacity(0.4)
            } else {
                ForEach(Array(model.thumbnails.enumerated()), id: \.offset) { _, thumb in
                    Image(nsImage: thumb)
                        .resizable()
                        .scaledToFill()
                        .frame(width: width / CGFloat(model.thumbnails.count),
                               height: Self.stripHeight)
                        .clipped()
                }
            }
        }
        .frame(width: width, height: Self.stripHeight)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func handle(at fraction: Double, width: CGFloat) -> some View {
        Capsule()
            .fill(.white)
            .frame(width: 6, height: Self.stripHeight + 8)
            .shadow(color: .black.opacity(0.6), radius: 2)
            .offset(x: width * fraction - 3)
            .allowsHitTesting(false)
    }
}

/// Owns the floating result panel: slides out from under the hotbar,
/// auto-hides after a countdown (paused while hovered, while Quick Look
/// is open, and during trimming).
@MainActor
final class CaptureResultController: NSObject {
    private let settings: SettingsStore

    init(settings: SettingsStore = .shared) {
        self.settings = settings
    }

    private static let cardWidth: CGFloat = 280
    private static let trimCardWidth: CGFloat = 420
    private static let displaySeconds: Double = 3
    private static let slideDistance: CGFloat = 26

    private let model = CaptureResultModel()
    private let ring = CaptureResultRing()
    private var panel: NSPanel?
    private var timer: Timer?
    private var remaining: Double = 0
    private var hovering = false
    private var quickLookOpen = false
    private var url: URL?
    private var quickLookCloseObserver: NSObjectProtocol?
    private var scrubGenerator: AVAssetImageGenerator?
    private var scrubInFlight = false
    private var pendingScrub: Double?
    /// Card-item rects in hosting-view coordinates, reported by the view
    /// during demo runs — resolved to screen rects on demand.
    private var demoLocalAnchors: [String: CGRect] = [:]

    var currentURL: URL? { url }

    /// Demo choreography: a chip's / the image's / the trim strip's current
    /// screen rect, by key (chip help string, "__image__", "__timeline__").
    func demoItemRect(_ key: String) -> CGRect? {
        guard let panel, panel.isVisible,
              let local = demoLocalAnchors[key] else { return nil }
        return Geometry.demoAnchorScreenRect(local: local, panelFrame: panel.frame)
    }

    func show(url: URL, isVideo: Bool, near anchor: CGRect?, on screen: NSScreen?) {
        self.url = url
        settings.recentCaptures = RecentCaptures.updated(settings.recentCaptures,
                                                         adding: url.path)
        model.ocrState = .idle
        model.isVideo = isVideo
        model.image = nil
        model.pill = nil
        model.trimming = false
        model.exporting = false
        model.scrubImage = nil
        model.thumbnails = []
        model.duration = 0
        model.copied = false
        scrubGenerator = nil
        if isVideo {
            loadVideoPreview(url: url)
        } else {
            model.image = NSImage(contentsOf: url)
        }
        let panel = ensurePanel()
        let size = normalSize()
        model.cardSize = size
        let target = targetOrigin(size: size, anchor: anchor, screen: screen)
        restartCountdown()
        let final = CGRect(origin: target, size: size)
        if panel.isVisible {
            panel.setFrame(final, display: true)
            return
        }
        // Fold out from under the hotbar: start tucked upward, slide down.
        var start = final
        start.origin.y += Self.slideDistance
        panel.alphaValue = 0
        panel.setFrame(start, display: false)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(final, display: true)
            panel.animator().alphaValue = 1
        }
    }

    func close() {
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
    }

    private func hide() {
        timer?.invalidate()
        timer = nil
        guard let panel, panel.isVisible else { return }
        var target = panel.frame
        target.origin.y += Self.slideDistance
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor in
                panel.orderOut(nil)
                panel.alphaValue = 1
            }
        })
    }

    // MARK: Countdown

    private func restartCountdown() {
        remaining = Self.displaySeconds
        ring.fraction = 1
        startTimer()
    }

    private func startTimer() {
        timer?.invalidate()
        let interval = 1.0 / 30
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard !self.hovering, !self.quickLookOpen,
                      !self.model.trimming, !self.model.exporting else { return }
                self.remaining -= interval
                self.ring.fraction = max(0, self.remaining / Self.displaySeconds)
                if self.remaining <= 0 {
                    self.hide()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: Actions

    private func copyFile() {
        guard let url else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
        model.copied = true
        // Give the user time to switch apps and paste.
        restartCountdown()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.model.copied = false
        }
    }

    /// The drag ghost: the capture aspect-fit into ~100 px, rounded — a
    /// compact proxy under the cursor.
    private func dragThumbnail() -> NSImage? {
        let maxSize = CGSize(width: 100, height: 100)
        guard let source = model.image, source.size.width > 0,
              source.size.height > 0 else { return nil }
        let scale = min(maxSize.width / source.size.width,
                        maxSize.height / source.size.height)
        let target = CGSize(width: max(1, source.size.width * scale),
                            height: max(1, source.size.height * scale))
        let thumb = NSImage(size: target)
        thumb.lockFocus()
        let rect = CGRect(origin: .zero, size: target)
        NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).addClip()
        source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.95)
        thumb.unlockFocus()
        return thumb
    }

    /// The card floats above screenSaver level, but the system draws the
    /// drag ghost at the (far lower) dragging window level — in front of
    /// the card the ghost would be invisible. Sink the card below the ghost
    /// for the duration of the drag session.
    private func setDragActive(_ active: Bool) {
        panel?.level = active
            ? .floating
            : NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
    }

    private func revealInFinder() {
        guard let url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        hide()
    }

    private func trash() {
        guard let url else { return }
        try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        settings.recentCaptures = RecentCaptures.removing(settings.recentCaptures,
                                                          path: url.path)
        hide()
    }

    private func copyText() {
        guard model.ocrState != .working,
              let image = model.image,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil,
                                          hints: nil) else { return }
        model.ocrState = .working
        Task { @MainActor in
            let text = await CaptureOCR.recognizeText(in: cgImage)
            if text.isEmpty {
                model.ocrState = .empty
            } else {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
                model.ocrState = .done
            }
            restartCountdown()
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            if model.ocrState != .working {
                model.ocrState = .idle
            }
        }
    }

    private func quickLook() {
        guard let qlPanel = QLPreviewPanel.shared() else { return }
        // Toggle: a second tap closes the peek (the willClose observer
        // resets the flag, also when the user closes it via Esc).
        if quickLookOpen, qlPanel.isVisible {
            qlPanel.close()
            return
        }
        quickLookOpen = true
        qlPanel.dataSource = self
        NSApp.activate(ignoringOtherApps: true)
        qlPanel.makeKeyAndOrderFront(nil)
        quickLookCloseObserver.map(NotificationCenter.default.removeObserver)
        quickLookCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: qlPanel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.quickLookOpen = false }
        }
    }

    // MARK: Trim

    private func beginTrim() {
        guard model.isVideo, let url, !model.trimming else { return }
        model.trimming = true
        model.trimIn = 0
        model.trimOut = 1
        loadThumbnails(url: url)
        animateCard(to: trimSize())
    }

    private func cancelTrim() {
        model.trimming = false
        model.scrubImage = nil
        animateCard(to: normalSize())
        restartCountdown()
    }

    private func applyTrim() {
        guard let url, !model.exporting, model.duration > 0,
              model.trimOut > model.trimIn else { return }
        // Full selection = nothing to cut.
        guard model.trimIn > 0.0005 || model.trimOut < 0.9995 else {
            cancelTrim()
            return
        }
        model.exporting = true
        let inSeconds = model.trimIn * model.duration
        let outSeconds = model.trimOut * model.duration
        Task { @MainActor in
            let asset = AVURLAsset(url: url)
            guard let export = AVAssetExportSession(
                asset: asset, presetName: AVAssetExportPresetPassthrough) else {
                model.exporting = false
                presentTrimError("The recording could not be opened for trimming.")
                return
            }
            let output = CaptureNaming.uniqueSiblingOnDisk(of: url, suffix: "_trim")
            export.outputURL = output
            export.outputFileType = .mp4
            export.timeRange = CMTimeRange(
                start: CMTime(seconds: inSeconds, preferredTimescale: 600),
                end: CMTime(seconds: outSeconds, preferredTimescale: 600))
            await withCheckedContinuation { continuation in
                export.exportAsynchronously { continuation.resume() }
            }
            model.exporting = false
            guard export.status == .completed else {
                presentTrimError(export.error?.localizedDescription
                                 ?? "Export failed.")
                return
            }
            // The card now represents the trimmed copy; the original stays.
            self.url = output
            settings.recentCaptures = RecentCaptures.updated(settings.recentCaptures,
                                                             adding: output.path)
            model.trimming = false
            model.scrubImage = nil
            loadVideoPreview(url: output)
            animateCard(to: normalSize())
            restartCountdown()
            NSSound(named: "Pop")?.play()
        }
    }

    /// Handle-drag position → the frame under the handle, throttled so at
    /// most one frame request runs at a time.
    private func scrub(_ fraction: Double?) {
        guard let fraction else {
            pendingScrub = nil
            model.scrubImage = nil
            return
        }
        pendingScrub = fraction
        guard !scrubInFlight, let url else { return }
        scrubInFlight = true
        if scrubGenerator == nil {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = CMTime(seconds: 0.25,
                                                            preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = generator.requestedTimeToleranceBefore
            generator.maximumSize = CGSize(width: 960, height: 0)
            scrubGenerator = generator
        }
        Task { @MainActor in
            while let next = pendingScrub {
                pendingScrub = nil
                let time = CMTime(seconds: next * model.duration, preferredTimescale: 600)
                if let cgImage = try? await scrubGenerator?.image(at: time).image,
                   model.trimming {
                    model.scrubImage = NSImage(cgImage: cgImage,
                                               size: CGSize(width: cgImage.width,
                                                            height: cgImage.height))
                }
            }
            scrubInFlight = false
        }
    }

    private func loadThumbnails(url: URL) {
        Task { @MainActor in
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 0, height: 88)
            generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5,
                                                            preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = generator.requestedTimeToleranceBefore
            let count = 8
            var thumbs: [NSImage] = []
            for index in 0..<count {
                let fraction = (Double(index) + 0.5) / Double(count)
                let time = CMTime(seconds: fraction * model.duration,
                                  preferredTimescale: 600)
                if let cgImage = try? await generator.image(at: time).image {
                    thumbs.append(NSImage(cgImage: cgImage,
                                          size: CGSize(width: cgImage.width,
                                                       height: cgImage.height)))
                }
            }
            if model.trimming {
                model.thumbnails = thumbs
            }
        }
    }

    private func presentTrimError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Trim failed"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    /// Harness hook (--result-card-test --ocr-test): run the copy-text chip
    /// and print what landed on the clipboard.
    func debugOCR() {
        copyText()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            let text = NSPasteboard.general.string(forType: .string) ?? ""
            let sample = text.prefix(80).replacingOccurrences(of: "\n", with: "⏎")
            print("OCR-TEST chars=\(text.count) sample=\(sample)")
        }
    }

    /// Harness hook (--result-card-test companions): open the trim UI and
    /// optionally export the given range, exactly like the UI's chips.
    func debugTrim(in inFraction: Double, out outFraction: Double, exportNow: Bool) {
        beginTrim()
        model.trimIn = inFraction
        model.trimOut = outFraction
        if exportNow {
            applyTrim()
        }
    }

    // MARK: Setup

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let actions = CaptureResultActions(
            copyFile: { [weak self] in self?.copyFile() },
            copyText: { [weak self] in self?.copyText() },
            dragURL: { [weak self] in self?.url },
            dragThumbnail: { [weak self] in self?.dragThumbnail() },
            dragActive: { [weak self] in self?.setDragActive($0) },
            revealInFinder: { [weak self] in self?.revealInFinder() },
            quickLook: { [weak self] in self?.quickLook() },
            beginTrim: { [weak self] in self?.beginTrim() },
            applyTrim: { [weak self] in self?.applyTrim() },
            cancelTrim: { [weak self] in self?.cancelTrim() },
            scrub: { [weak self] in self?.scrub($0) },
            trash: { [weak self] in self?.trash() },
            hoverChanged: { [weak self] in self?.hovering = $0 },
            reportItemBounds: { [weak self] in self?.demoLocalAnchors = $0 })
        let hosting = NSHostingView(rootView: CaptureResultView(
            model: model, ring: ring, actions: actions))
        // No window auto-layout and no safe-area tracking in a floating
        // panel — invalidations during a constraint flush crash (see the
        // hotbar's identical guard). The card is sized explicitly; its root
        // view pins itself to cardSize, so nothing needs intrinsic sizing.
        hosting.sizingOptions = []
        hosting.safeAreaRegions = []
        let panel = NSPanel(contentRect: CGRect(x: 0, y: 0,
                                                width: Self.cardWidth, height: 160),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = hosting
        // Above the dim like the hotbar; level is set last (isFloatingPanel
        // and friends silently reset it).
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        self.panel = panel
        return panel
    }

    private func imageAspect() -> CGFloat {
        guard let image = model.image, image.size.height > 0 else { return 16.0 / 9 }
        return image.size.width / image.size.height
    }

    private func normalSize() -> CGSize {
        CGSize(width: Self.cardWidth,
               height: min(200, max(90, Self.cardWidth / imageAspect())))
    }

    private func trimSize() -> CGSize {
        let imageHeight = min(236, max(140, Self.trimCardWidth / imageAspect()))
        return CGSize(width: Self.trimCardWidth,
                      height: imageHeight + CaptureResultView.timelineHeight + 8)
    }

    /// Grows/shrinks the visible card around its top edge, centered
    /// horizontally, clamped to the screen.
    private func animateCard(to size: CGSize) {
        model.cardSize = size
        guard let panel, panel.isVisible else { return }
        var frame = panel.frame
        frame.origin.x -= (size.width - frame.width) / 2
        frame.origin.y = frame.maxY - size.height
        frame.size = size
        if let bounds = panel.screen?.visibleFrame {
            frame.origin.x = min(max(frame.origin.x, bounds.minX + 8),
                                 bounds.maxX - size.width - 8)
            frame.origin.y = min(max(frame.origin.y, bounds.minY + 8),
                                 bounds.maxY - size.height - 8)
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        }
    }

    private func targetOrigin(size: CGSize, anchor: CGRect?,
                              screen: NSScreen?) -> CGPoint {
        let bounds = screen?.visibleFrame
            ?? NSScreen.screens.first?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
        let anchor = anchor ?? CGRect(x: bounds.maxX - size.width - 20,
                                      y: bounds.maxY - 20, width: size.width, height: 0)
        var origin = CGPoint(x: anchor.midX - size.width / 2,
                             y: anchor.minY - size.height - 10)
        origin.x = min(max(origin.x, bounds.minX + 8), bounds.maxX - size.width - 8)
        origin.y = min(max(origin.y, bounds.minY + 8), bounds.maxY - size.height - 8)
        return origin
    }

    private func loadVideoPreview(url: URL) {
        Task { @MainActor in
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            let duration = (try? await asset.load(.duration)).map(CMTimeGetSeconds) ?? 0
            model.duration = duration
            if let cgImage = try? await generator.image(at: .zero).image {
                model.image = NSImage(cgImage: cgImage,
                                      size: CGSize(width: cgImage.width,
                                                   height: cgImage.height))
                if panel?.isVisible == true, !model.trimming {
                    animateCard(to: normalSize())
                }
            }
            let bytes = (try? FileManager.default
                .attributesOfItem(atPath: url.path)[.size] as? Int64) ?? nil
            model.pill = Self.pillText(seconds: duration, bytes: bytes)
        }
    }

    static func pillText(seconds: Double, bytes: Int64?) -> String {
        let duration = TrimMath.timeString(seconds.rounded())
        guard let bytes else { return duration }
        let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        return "\(duration) · \(size)"
    }
}

extension CaptureResultController: QLPreviewPanelDataSource {
    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { 1 }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!,
                                  previewItemAt index: Int) -> QLPreviewItem! {
        MainActor.assumeIsolated { url as NSURL? }
    }
}
