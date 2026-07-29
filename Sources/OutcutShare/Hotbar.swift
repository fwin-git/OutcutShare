import AppKit
import SwiftUI

@MainActor
final class HotbarModel: ObservableObject {
    @Published var isPaused = false
    @Published var isRecording = false
    @Published var followOn = false
    @Published var followTarget: FollowMode = .activeWindow
    @Published var followMenuOpen = false
    @Published var highlightsOn = false
    @Published var previewOn = false
    /// Runs along a region edge instead of top/bottom: buttons stack, the
    /// follow label collapses to icon + chevron.
    @Published var vertical = false
    @Published var ocrState: OCRChipState = .idle
    /// Virtual-monitor sessions have no on-screen region: adjust, presets,
    /// follow and highlights don't apply and their buttons are hidden.
    @Published var regionless = false
}

struct HotbarActions {
    var stop: () -> Void
    var pause: () -> Void
    var record: () -> Void
    var screenshot: () -> Void
    var copyText: () -> Void
    var toggleOrientation: () -> Void
    var highlights: () -> Void
    var preview: () -> Void
    var adjust: () -> Void
    var savePreset: () -> Void
    var follow: () -> Void
    var followMenu: () -> Void
    var selectFollow: (FollowMode) -> Void
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
            // Drawn in-panel like the tooltip below: a real NSMenu opens at
            // popup level, which sits underneath this screenSaver+1 panel.
            if model.followMenuOpen && !model.regionless {
                if model.vertical {
                    followMenu
                } else {
                    followMenu
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 48)
                }
            }
            // In-panel tooltip: system tooltips render at popup level, which
            // sits below this panel — they'd be invisible. The label stays in
            // the view tree permanently (opacity swap, plain background):
            // inserting a material view on hover makes the window server
            // rebuild the panel backdrop and stalls the app.
            Text(hoverLabel ?? " ")
                .font(.caption)
                .lineLimit(1)
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.72), in: Capsule())
                .opacity(hoverLabel == nil ? 0 : 1)
                .frame(height: 22)
        }
        .fixedSize()
    }

    private var bar: some View {
        Group {
            if model.vertical {
                VStack(spacing: 13) { barItems }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 14)
            } else {
                HStack(spacing: 13) { barItems }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
        }
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.15)))
    }

    @ViewBuilder
    private var barItems: some View {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .contentShape(Rectangle())
                // Click = rotate the bar; drag (≥ 10 pt) = move it.
                .onTapGesture { actions.toggleOrientation() }
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
                .onHover { hover(hover: $0, label: "Move (drag) / rotate (click)") }

            barButton("stop.fill", help: "Stop sharing", action: actions.stop)
            barButton(model.isPaused ? "play.fill" : "pause.fill",
                      help: model.isPaused ? "Resume sharing" : "Pause sharing",
                      active: model.isPaused, action: actions.pause)
            barButton(model.isRecording ? "stop.circle.fill" : "record.circle",
                      help: model.isRecording ? "Stop recording" : "Start recording",
                      tint: model.isRecording ? .red : nil, action: actions.record)
            barButton("camera", help: "Screenshot shared region",
                      action: actions.screenshot)
            barButton(ocrSymbol, help: "Copy text in region (OCR)",
                      action: actions.copyText)
            if !model.regionless {
                barButton("cursorarrow.rays", help: "Presenter highlights",
                          active: model.highlightsOn, action: actions.highlights)
            }
            barButton("eye", help: "Preview shared output",
                      active: model.previewOn, action: actions.preview)
            if !model.regionless {
                barButton("arrow.up.left.and.arrow.down.right", help: "Move / resize region",
                          action: actions.adjust)
                barButton("plus.square.on.square", help: "Save region as preset",
                          action: actions.savePreset)
                followControl
            }

            if model.vertical {
                Divider().frame(width: 16)
            } else {
                Divider().frame(height: 16)
            }

            Button(action: actions.hide) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .onHover { hover(hover: $0, label: "Hide hotbar") }
    }

    private var ocrSymbol: String {
        switch model.ocrState {
        case .done: return "checkmark"
        case .empty: return "questionmark"
        default: return "text.viewfinder"
        }
    }

    /// Split control: the icon toggles the selected follow target on/off,
    /// the label (dropped in vertical bars) + chevron open the dropdown.
    @ViewBuilder
    private var followControl: some View {
        let scope = barButton("scope",
                              help: model.followOn ? "Stop following"
                                                   : "Follow \(shortLabel(model.followTarget))",
                              active: model.followOn, action: actions.follow)
        let menuButton = Button(action: actions.followMenu) {
            HStack(spacing: 2) {
                if !model.vertical {
                    Text(shortLabel(model.followTarget))
                        .font(.caption)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .rotationEffect(model.followMenuOpen ? .degrees(180) : .zero)
            }
            .padding(model.vertical ? .horizontal : .vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(model.followOn ? AnyShapeStyle(Color.accentColor)
                                        : AnyShapeStyle(.secondary))
        .onHover { hover(hover: $0, label: "Choose follow mode") }

        if model.vertical {
            VStack(spacing: 2) {
                scope
                menuButton
            }
        } else {
            HStack(spacing: 3) {
                scope
                menuButton
            }
        }
    }

    private var followMenu: some View {
        VStack(alignment: .leading, spacing: 2) {
            followMenuItem(.activeWindow)
            followMenuItem(.cursor)
        }
        .padding(6)
        .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
    }

    private func followMenuItem(_ mode: FollowMode) -> some View {
        Button(action: { actions.selectFollow(mode) }) {
            HStack(spacing: 5) {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .semibold))
                    .opacity(model.followTarget == mode && model.followOn ? 1 : 0)
                Text(mode.displayName)
                    .font(.caption)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func shortLabel(_ mode: FollowMode) -> String {
        mode == .cursor ? "Cursor" : "Window"
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
    private var panelGestureAttached: Bool?
    private var lastPanelMoveAt: TimeInterval = 0
    private var lastFollowMode: FollowMode = .off
    /// Grabber-click override; nil = orientation follows auto-placement.
    private var verticalOverride: Bool?
    /// Footprint of the horizontal bar — the auto-side decision always
    /// reasons about whether THAT would fit below/above.
    private var lastHorizontalSize: CGSize?

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
        model.followMenuOpen = false
        refresh()
        // The button set varies by mode (regionless hides region actions) —
        // refit the panel to the current content.
        if let panel, let hosting = panel.contentView as? NSHostingView<HotbarView> {
            panel.setContentSize(hosting.fittingSize)
        }
        position()
        panel?.orderFrontRegardless()
    }

    func regionChanged(_ region: CGRect) {
        lastRegion = region
        guard panel?.isVisible == true else { return }
        // Cursor follow chases the pointer: a bar docked to the region would
        // retreat from the approaching cursor forever and stay unreachable.
        // Freeze it; refresh() re-attaches it when cursor follow ends.
        guard settings.followMode != .cursor else { return }
        position()
    }

    /// Monitor mode: the preview panel moved or resized. The hotbar follows
    /// while it sits near the panel (auto placement re-runs; a manual spot
    /// keeps its relative offset). Parked far away, it stays — that
    /// placement was deliberate. Attachment is decided ONCE at the start of
    /// each drag gesture and held: a detached panel dragged past the hotbar
    /// must not pick it up mid-flight.
    func panelMoved(to frame: CGRect) {
        let previous = lastRegion
        lastRegion = frame
        guard let panel, panel.isVisible, previous != frame else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let isNewGesture = now - lastPanelMoveAt > 0.4
        lastPanelMoveAt = now
        if isNewGesture {
            panelGestureAttached = Geometry.framesAreNear(panel.frame, previous,
                                                          threshold: 80)
        }
        guard panelGestureAttached == true else { return }
        if let manual = manualOrigin {
            let moved = CGPoint(x: manual.x + frame.minX - previous.minX,
                                y: manual.y + frame.minY - previous.minY)
            manualOrigin = moved
            panel.setFrameOrigin(clamped(moved, size: panel.frame.size))
        } else {
            position()
        }
    }

    func close() {
        panel?.orderOut(nil)
        manualOrigin = nil
        verticalOverride = nil
        model.followMenuOpen = false
    }

    /// Anchor for companion panels (the capture-result preview docks below).
    var currentFrame: CGRect? {
        guard let panel, panel.isVisible else { return nil }
        return panel.frame
    }

    func refresh() {
        model.isPaused = session?.isPaused ?? false
        model.isRecording = session?.isRecording ?? false
        let followMode = settings.followMode
        model.followOn = followMode != .off
        // The dropdown's target mirrors the last non-off mode, however it
        // was enabled (hotbar, menu bar, URL scheme).
        if followMode != .off, settings.followTarget != followMode {
            settings.followTarget = followMode
        }
        model.followTarget = settings.followTarget
        if lastFollowMode == .cursor, followMode != .cursor,
           panel?.isVisible == true {
            // Parked far from the region while cursor follow ran — glide
            // back to the docked spot instead of teleporting.
            position(animated: true)
        }
        lastFollowMode = followMode
        model.highlightsOn = settings.cursorHighlight || settings.clickRipples
        model.previewOn = settings.previewWindowEnabled
        model.regionless = session?.isVirtualMonitor ?? false
    }

    private func position(animated: Bool = false) {
        guard let panel else { return }
        if let manualOrigin {
            panel.setFrameOrigin(clamped(manualOrigin, size: panel.frame.size))
            return
        }
        // The side decision reasons about the horizontal footprint; forced
        // to a vertical edge (auto) — or overridden — the bar stacks.
        let horizontal = model.vertical
            ? (lastHorizontalSize
               ?? CGSize(width: panel.frame.height, height: panel.frame.width))
            : panel.frame.size
        let side = Geometry.hotbarSide(barSize: horizontal, region: lastRegion,
                                       screenFrame: screenFrame, gap: 12)
        let wantVertical = verticalOverride ?? side.isVerticalEdge
        if wantVertical != model.vertical {
            applyOrientation(wantVertical)
            return
        }
        let origin = Geometry.hotbarOrigin(barSize: panel.frame.size, region: lastRegion,
                                           screenFrame: screenFrame, gap: 12, side: side)
        guard animated else {
            panel.setFrameOrigin(origin)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(CGRect(origin: origin, size: panel.frame.size),
                                      display: true)
        }
    }

    /// Grabber click: rotate in place (and stop auto-orientation for the
    /// session, like a manual drag stops auto-placement).
    private func toggleOrientation() {
        verticalOverride = !model.vertical
        applyOrientation(verticalOverride!)
    }

    private func applyOrientation(_ vertical: Bool) {
        guard model.vertical != vertical else { return }
        if !model.vertical, let panel {
            lastHorizontalSize = panel.frame.size
        }
        model.vertical = vertical
        model.followMenuOpen = false
        // The hosting view lays the rotated bar out on the next runloop
        // pass — only then does fittingSize match the new orientation.
        DispatchQueue.main.async { [weak self] in
            guard let self, let panel = self.panel,
                  let hosting = panel.contentView as? NSHostingView<HotbarView> else { return }
            hosting.layoutSubtreeIfNeeded()
            panel.setContentSize(hosting.fittingSize)
            self.position()
        }
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
            screenshot: { [weak self] in self?.session?.captureScreenshot() },
            copyText: { [weak self] in self?.copyRegionText() },
            toggleOrientation: { [weak self] in self?.toggleOrientation() },
            highlights: { [weak self] in self?.toggleHighlights() },
            preview: { [weak self] in self?.togglePreview() },
            adjust: { [weak self] in self?.session?.startAdjust() },
            savePreset: { [weak self] in
                guard let session = self?.session else { return }
                PresetPrompt.run(session: session)
            },
            follow: { [weak self] in self?.toggleFollow() },
            followMenu: { [weak self] in self?.toggleFollowMenu() },
            selectFollow: { [weak self] in self?.selectFollow($0) },
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

    /// The session's settings observer shows/hides the panel.
    private func togglePreview() {
        settings.previewWindowEnabled.toggle()
        refresh()
    }

    private func copyRegionText() {
        guard model.ocrState != .working else { return }
        model.ocrState = .working
        Task { [weak self] in
            let found = await self?.session?.copyRegionTextToClipboard() ?? false
            guard let self else { return }
            self.model.ocrState = found ? .done : .empty
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            if self.model.ocrState != .working {
                self.model.ocrState = .idle
            }
        }
    }

    private func toggleFollow() {
        setFollowMenu(open: false)
        if settings.followMode == .off {
            settings.followMode = settings.followTarget
        } else {
            settings.followMode = .off
        }
        refresh()
    }

    private func selectFollow(_ mode: FollowMode) {
        settings.followTarget = mode
        settings.followMode = mode
        setFollowMenu(open: false)
        refresh()
    }

    private func toggleFollowMenu() {
        setFollowMenu(open: !model.followMenuOpen)
    }

    private func setFollowMenu(open: Bool) {
        guard model.followMenuOpen != open else { return }
        model.followMenuOpen = open
        // The hosting view lays the dropdown out on the next runloop pass —
        // only then does fittingSize include it.
        DispatchQueue.main.async { [weak self] in self?.refitPanel() }
    }

    /// Resize to the current content, keeping the bar's top edge in place
    /// so the dropdown appears to fold out underneath.
    private func refitPanel() {
        guard let panel,
              let hosting = panel.contentView as? NSHostingView<HotbarView> else { return }
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        guard size != panel.frame.size else { return }
        let origin = CGPoint(x: panel.frame.origin.x,
                             y: panel.frame.maxY - size.height)
        panel.setFrame(CGRect(origin: clamped(origin, size: size), size: size),
                       display: true)
    }

    /// ✕ turns the setting itself off, so the menu/settings checkboxes stay
    /// truthful; re-checking either brings the bar back.
    private func hideForSession() {
        panel?.orderOut(nil)
        settings.hotbarEnabled = false
    }
}
