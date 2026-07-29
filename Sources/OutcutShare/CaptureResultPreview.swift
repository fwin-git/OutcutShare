import AppKit
import AVFoundation
import Quartz
import SwiftUI

@MainActor
final class CaptureResultModel: ObservableObject {
    @Published var image: NSImage?
    @Published var isVideo = false
    @Published var pill: String?
}

/// Countdown fraction on its own tiny observable: only the ring view
/// observes it, so 30 Hz updates don't re-render (and leak observation
/// registrations for) the whole card — see the macOS 26 note in AGENTS.md.
@MainActor
final class CaptureResultRing: ObservableObject {
    @Published var fraction: Double = 1
}

struct CaptureResultActions {
    var revealInFinder: () -> Void
    var quickLook: () -> Void
    var trash: () -> Void
    var hoverChanged: (Bool) -> Void
}

/// The card that folds out under the hotbar after a capture: the shot (or
/// the recording's poster), corner chips styled like the shared-output
/// preview's pause button, a countdown ring and a duration/size pill.
struct CaptureResultView: View {
    @ObservedObject var model: CaptureResultModel
    @ObservedObject var ring: CaptureResultRing
    let actions: CaptureResultActions

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image = model.image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.black.opacity(0.4)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.white.opacity(0.25)))

            HStack(spacing: 6) {
                chip("folder", help: "Show in Finder", action: actions.revealInFinder)
                chip("eye", help: model.isVideo ? "Preview with playback" : "Preview large",
                     action: actions.quickLook)
                chip("trash", help: "Delete file", action: actions.trash)
            }
            .padding(6)

            ringView
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity,
                       alignment: .topLeading)

            if let pill = model.pill {
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
        .onHover { actions.hoverChanged($0) }
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
    }
}

/// Owns the floating result panel: slides out from under the hotbar,
/// auto-hides after a countdown (paused while hovered or while Quick Look
/// is open).
@MainActor
final class CaptureResultController: NSObject {
    private static let cardWidth: CGFloat = 280
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

    func show(url: URL, isVideo: Bool, near anchor: CGRect?, on screen: NSScreen?) {
        self.url = url
        model.isVideo = isVideo
        model.image = nil
        model.pill = nil
        if isVideo {
            loadVideoPreview(url: url)
        } else {
            model.image = NSImage(contentsOf: url)
        }
        let panel = ensurePanel()
        let aspect = imageAspect()
        let height = min(200, max(90, Self.cardWidth / aspect))
        let size = CGSize(width: Self.cardWidth, height: height)
        let target = targetOrigin(size: size, anchor: anchor, screen: screen)
        remaining = Self.displaySeconds
        ring.fraction = 1
        startTimer()
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

    private func startTimer() {
        timer?.invalidate()
        let interval = 1.0 / 30
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard !self.hovering, !self.quickLookOpen else { return }
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

    private func revealInFinder() {
        guard let url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        hide()
    }

    private func trash() {
        guard let url else { return }
        try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        hide()
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

    // MARK: Setup

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let actions = CaptureResultActions(
            revealInFinder: { [weak self] in self?.revealInFinder() },
            quickLook: { [weak self] in self?.quickLook() },
            trash: { [weak self] in self?.trash() },
            hoverChanged: { [weak self] in self?.hovering = $0 })
        let hosting = NSHostingView(rootView: CaptureResultView(
            model: model, ring: ring, actions: actions))
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
            if let cgImage = try? await generator.image(at: .zero).image {
                model.image = NSImage(cgImage: cgImage,
                                      size: CGSize(width: cgImage.width,
                                                   height: cgImage.height))
                resizeToImage()
            }
            let bytes = (try? FileManager.default
                .attributesOfItem(atPath: url.path)[.size] as? Int64) ?? nil
            model.pill = Self.pillText(seconds: duration, bytes: bytes)
        }
    }

    /// The poster arrives async — refit the visible panel to its aspect.
    private func resizeToImage() {
        guard let panel, panel.isVisible else { return }
        let height = min(200, max(90, Self.cardWidth / imageAspect()))
        var frame = panel.frame
        frame.origin.y += frame.height - height
        frame.size.height = height
        panel.animator().setFrame(frame, display: true)
    }

    static func pillText(seconds: Double, bytes: Int64?) -> String {
        let total = Int(seconds.rounded())
        let duration = total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
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
