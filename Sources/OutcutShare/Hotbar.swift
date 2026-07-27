import AppKit
import SwiftUI

@MainActor
final class HotbarModel: ObservableObject {
    @Published var isPaused = false
    @Published var isRecording = false
    @Published var followOn = false
    @Published var highlightsOn = false
}

struct HotbarActions {
    var stop: () -> Void
    var pause: () -> Void
    var record: () -> Void
    var highlights: () -> Void
    var adjust: () -> Void
    var savePreset: () -> Void
    var follow: () -> Void
    var hide: () -> Void
    var beginDrag: () -> Void
    var drag: () -> Void
    var endDrag: () -> Void
}

struct HotbarView: View {
    @ObservedObject var model: HotbarModel
    let actions: HotbarActions
    @State private var dragging = false
    @State private var hoverLabel: String?

    var body: some View {
        VStack(spacing: 5) {
            bar
            // In-panel tooltip: system tooltips render at popup level, which
            // sits below this panel — they'd be invisible.
            Group {
                if let hoverLabel {
                    Text(hoverLabel)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.ultraThinMaterial, in: Capsule())
                }
            }
            .frame(height: 22)
        }
        .fixedSize()
    }

    private var bar: some View {
        HStack(spacing: 13) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .contentShape(Rectangle())
                .gesture(
                    // Positioning is driven by NSEvent.mouseLocation, not the
                    // gesture's translation: the gesture's coordinate space
                    // moves with the panel, which would feed back into itself
                    // and make the bar jitter.
                    DragGesture(coordinateSpace: .global)
                        .onChanged { _ in
                            if !dragging {
                                dragging = true
                                actions.beginDrag()
                            }
                            actions.drag()
                        }
                        .onEnded { _ in
                            dragging = false
                            actions.endDrag()
                        }
                )
                .onHover { hover(hover: $0, label: "Move hotbar") }

            barButton("stop.fill", help: "Stop sharing", action: actions.stop)
            barButton(model.isPaused ? "play.fill" : "pause.fill",
                      help: model.isPaused ? "Resume sharing" : "Pause sharing",
                      active: model.isPaused, action: actions.pause)
            barButton(model.isRecording ? "stop.circle.fill" : "record.circle",
                      help: model.isRecording ? "Stop recording" : "Start recording",
                      tint: model.isRecording ? .red : nil, action: actions.record)
            barButton("cursorarrow.rays", help: "Presenter highlights",
                      active: model.highlightsOn, action: actions.highlights)
            barButton("arrow.up.left.and.arrow.down.right", help: "Move / resize region",
                      action: actions.adjust)
            barButton("plus.square.on.square", help: "Save region as preset",
                      action: actions.savePreset)
            barButton("scope", help: "Follow mode",
                      active: model.followOn, action: actions.follow)

            Divider().frame(height: 16)

            Button(action: actions.hide) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .onHover { hover(hover: $0, label: "Hide hotbar (turns the setting off)") }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.15)))
    }

    private func hover(hover: Bool, label: String) {
        if hover {
            hoverLabel = label
        } else if hoverLabel == label {
            hoverLabel = nil
        }
    }

    private func barButton(_ symbol: String, help: String, active: Bool = false,
                           tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint ?? (active ? Color.accentColor : Color.primary))
        .onHover { hover(hover: $0, label: help) }
    }
}

/// Floating quick-action bar next to the region border. Auto-positions
/// below → side → top of the region; a grabber allows manual repositioning
/// (which then sticks for the session) and ✕ hides it for the session.
@MainActor
final class HotbarController {
    private weak var session: ShareSession?
    private let settings: SettingsStore
    let model = HotbarModel()
    private var panel: NSPanel?
    private var manualOrigin: CGPoint?
    private var dragAnchor: (origin: CGPoint, mouse: CGPoint)?
    private var screenFrame: CGRect = .zero
    private var lastRegion: CGRect = .zero
    private var lastFollowChoice: FollowMode = .activeWindow

    init(session: ShareSession, settings: SettingsStore) {
        self.session = session
        self.settings = settings
    }

    func show(region: CGRect, screen: NSScreen) {
        screenFrame = screen.frame
        lastRegion = region
        if panel == nil {
            build()
        }
        refresh()
        position()
        panel?.orderFrontRegardless()
    }

    func regionChanged(_ region: CGRect) {
        lastRegion = region
        guard panel?.isVisible == true else { return }
        position()
    }

    func close() {
        panel?.orderOut(nil)
        manualOrigin = nil
    }

    func refresh() {
        model.isPaused = session?.isPaused ?? false
        model.isRecording = session?.isRecording ?? false
        model.followOn = settings.followMode != .off
        model.highlightsOn = settings.cursorHighlight || settings.clickRipples
    }

    private func position() {
        guard let panel else { return }
        if let manualOrigin {
            panel.setFrameOrigin(clamped(manualOrigin, size: panel.frame.size))
            return
        }
        panel.setFrameOrigin(Geometry.hotbarOrigin(barSize: panel.frame.size,
                                                   region: lastRegion,
                                                   screenFrame: screenFrame, gap: 12))
    }

    private func clamped(_ origin: CGPoint, size: CGSize) -> CGPoint {
        CGPoint(x: min(max(origin.x, screenFrame.minX), screenFrame.maxX - size.width),
                y: min(max(origin.y, screenFrame.minY), screenFrame.maxY - size.height))
    }

    private func build() {
        let actions = HotbarActions(
            stop: { [weak self] in self?.session?.stop() },
            pause: { [weak self] in self?.session?.togglePause() },
            record: { [weak self] in self?.session?.toggleRecording() },
            highlights: { [weak self] in self?.toggleHighlights() },
            adjust: { [weak self] in self?.session?.startAdjust() },
            savePreset: { [weak self] in
                guard let session = self?.session else { return }
                PresetPrompt.run(session: session)
            },
            follow: { [weak self] in self?.toggleFollow() },
            hide: { [weak self] in self?.hideForSession() },
            beginDrag: { [weak self] in
                guard let self, let panel = self.panel else { return }
                self.dragAnchor = (panel.frame.origin, NSEvent.mouseLocation)
            },
            drag: { [weak self] in
                guard let self, let panel = self.panel,
                      let anchor = self.dragAnchor else { return }
                let mouse = NSEvent.mouseLocation
                let origin = CGPoint(x: anchor.origin.x + mouse.x - anchor.mouse.x,
                                     y: anchor.origin.y + mouse.y - anchor.mouse.y)
                panel.setFrameOrigin(self.clamped(origin, size: panel.frame.size))
            },
            endDrag: { [weak self] in
                self?.dragAnchor = nil
                self?.manualOrigin = self?.panel?.frame.origin
            })

        let hosting = NSHostingView(rootView: HotbarView(model: model, actions: actions))
        let size = hosting.fittingSize
        hosting.frame = CGRect(origin: .zero, size: size)
        let panel = NSPanel(contentRect: CGRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.becomesKeyOnlyIfNeeded = true
        // One above the dim overlay (.screenSaver) so the bar is never dimmed.
        // Must come after other panel setup: properties like isFloatingPanel
        // silently reset the window level.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.contentView = hosting
        self.panel = panel
    }

    private func toggleHighlights() {
        let enable = !(settings.cursorHighlight || settings.clickRipples)
        settings.cursorHighlight = enable
        settings.clickRipples = enable
        refresh()
    }

    private func toggleFollow() {
        if settings.followMode == .off {
            settings.followMode = lastFollowChoice
        } else {
            lastFollowChoice = settings.followMode
            settings.followMode = .off
        }
        refresh()
    }

    /// ✕ turns the setting itself off, so the menu/settings checkboxes stay
    /// truthful; re-checking either brings the bar back.
    private func hideForSession() {
        panel?.orderOut(nil)
        settings.hotbarEnabled = false
    }
}
