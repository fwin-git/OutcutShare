import AppKit
import SwiftUI

/// Shared playback state between the demo canvas and surrounding controls:
/// autoplay by default, toggled by the play/pause controls; `progress`
/// tracks the position in the demo cycle.
@MainActor
final class FollowDemoModel: ObservableObject {
    /// Autoplay by default; the play/pause control toggles this.
    @Published var playing = true
    @Published var progress: Double = 0
}

/// Reusable live preview of the sharing experience: fake desktop, styled
/// region with dimming, cursor emphasis, optional mini hotbar, optional
/// paused-state rendering, and an optional animated follow-mode demo.
/// All geometry is kept in unit space (0…1) and scaled at render time so the
/// demo timer can run without knowing the canvas size.
struct RegionPreviewCanvas: View {
    @ObservedObject var settings: SettingsStore
    var showsHotbar = false
    var paused = false
    var showsCursor = true
    /// While true the follow demo plays (autoplay-driven via FollowDemoModel).
    var demoActive = false
    var demoModel: FollowDemoModel? = nil
    /// Shows a mock notification banner unless banners are hidden from viewers.
    var showsNotificationDemo = false

    // Unit-space scene layout.
    private static let windowsU: [CGRect] = [
        CGRect(x: 0.13, y: 0.24, width: 0.42, height: 0.5),
        CGRect(x: 0.51, y: 0.4, width: 0.34, height: 0.42),
        CGRect(x: 0.7, y: 0.1, width: 0.22, height: 0.26),
    ]
    private static let defaultRegionU = CGRect(x: 0.18, y: 0.16, width: 0.56, height: 0.62)
    private static let defaultCursorU = CGPoint(x: 0.55, y: 0.55)

    @State private var regionU = Self.defaultRegionU
    @State private var cursorU = Self.defaultCursorU
    @State private var step = 0
    @State private var rippleID = 0
    // @State keeps the publishers stable across re-renders — the fine-grained
    // progress updates re-render this view constantly, and per-render timer
    // instances would reset before ever firing.
    @State private var demoTimer = Timer.publish(every: 1.6, on: .main, in: .common).autoconnect()
    @State private var progressTimer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()
    @State private var rippleTimer = Timer.publish(every: 1.7, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let region = scaled(regionU, in: size)
            let cursor = CGPoint(x: cursorU.x * size.width, y: cursorU.y * size.height)
            ZStack {
                desktop(size: size)
                if settings.dimmingEnabled {
                    DimShape(cutout: region, cornerRadius: CGFloat(settings.borderRadius))
                        .fill(Color.black.opacity(settings.dimOpacity),
                              style: FillStyle(eoFill: true))
                }
                if paused {
                    pauseOverlay(region: region)
                }
                if settings.showRegionBorder {
                    border(for: region)
                }
                if showsCursor {
                    if settings.clickRipples && !paused {
                        RippleDot(color: .yellow)
                            .frame(width: 44, height: 44)
                            .position(cursor)
                            .id(rippleID)
                    }
                    if settings.cursorHighlight {
                        Circle()
                            .fill(Color.yellow.opacity(0.28))
                            .overlay(Circle().strokeBorder(Color.yellow.opacity(0.85),
                                                           lineWidth: 1.5))
                            .frame(width: 26, height: 26)
                            .position(cursor)
                    }
                    Image(nsImage: NSCursor.arrow.image)
                        .position(x: cursor.x + 5, y: cursor.y + 7)
                }
                if showsNotificationDemo && !settings.hideNotificationBanners {
                    notificationBanner
                        .position(x: size.width - 66, y: 22)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
                if showsHotbar && settings.hotbarEnabled {
                    miniHotbar
                        .position(x: region.midX,
                                  y: min(region.maxY + 16, size.height - 12))
                }
            }
            .animation(.easeOut(duration: 0.3), value: settings.hideNotificationBanners)
            .onReceive(rippleTimer) { _ in
                if settings.clickRipples && showsCursor && !paused {
                    rippleID += 1
                }
            }
            .onReceive(demoTimer) { _ in
                advanceDemo()
            }
            .onReceive(progressTimer) { _ in
                // Fine-grained fill so pausing freezes the ring instantly.
                guard demoActive, let model = demoModel else { return }
                model.progress = min(model.progress + 0.05 / 4.8, 1)
            }
            .onChange(of: demoActive) { _, active in
                // Pausing freezes in place; resuming steps immediately
                // instead of waiting for the next timer tick.
                if active {
                    advanceDemo()
                }
            }
            .onAppear {
                if demoActive {
                    advanceDemo()
                }
            }
        }
        .frame(height: 190)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
    }

    // MARK: Follow demo

    private func advanceDemo() {
        guard demoActive else { return }
        step += 1
        reportProgress()
        let window = Self.windowsU[step % Self.windowsU.count]
        let target = CGPoint(x: window.midX, y: window.midY)
        // The cursor does its rounds in every mode — with follow off, the
        // region simply doesn't react, which is exactly what "off" means.
        withAnimation(.easeInOut(duration: 0.5)) {
            cursorU = target
        }
        let regionTarget: CGRect
        switch settings.followMode {
        case .activeWindow:
            regionTarget = settings.followResizes
                ? window.insetBy(dx: -0.02, dy: -0.03)
                : centered(Self.defaultRegionU.size, on: target)
        case .cursor:
            // Camera-style trailing: region centers slightly behind the cursor.
            regionTarget = centered(Self.defaultRegionU.size,
                                    on: CGPoint(x: target.x - 0.03, y: target.y + 0.02))
        case .off:
            withAnimation(.easeOut(duration: 0.4)) {
                regionU = Self.defaultRegionU
            }
            return
        }
        // The region reacts after the cursor starts moving, like real usage.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if settings.followBehavior == .glide {
                withAnimation(.easeOut(duration: 0.55)) {
                    regionU = regionTarget
                }
            } else {
                regionU = regionTarget
            }
        }
    }

    private func reportProgress() {
        // Snap to the exact phase baseline; the fine timer fills in between.
        guard let model = demoModel else { return }
        let phase = step % Self.windowsU.count
        model.progress = Double(phase) / Double(Self.windowsU.count)
    }

    private func centered(_ size: CGSize, on center: CGPoint) -> CGRect {
        var rect = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                          width: size.width, height: size.height)
        rect.origin.x = min(max(rect.origin.x, 0.02), 0.98 - size.width)
        rect.origin.y = min(max(rect.origin.y, 0.02), 0.98 - size.height)
        return rect
    }

    private func scaled(_ unit: CGRect, in size: CGSize) -> CGRect {
        CGRect(x: unit.minX * size.width, y: unit.minY * size.height,
               width: unit.width * size.width, height: unit.height * size.height)
    }

    // MARK: Scene pieces

    private func desktop(size: CGSize) -> some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.16, green: 0.22, blue: 0.42),
                                    Color(red: 0.45, green: 0.25, blue: 0.45)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            ForEach(Array(Self.windowsU.enumerated()), id: \.offset) { index, unit in
                let rect = scaled(unit, in: size)
                RoundedRectangle(cornerRadius: 6)
                    .fill(index == 0 ? Color.white.opacity(0.82)
                          : index == 1 ? Color(nsColor: .windowBackgroundColor).opacity(0.9)
                          : Color.white.opacity(0.25))
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }
        }
    }

    private func pauseOverlay(region: CGRect) -> some View {
        Group {
            if settings.pauseStyle == .privacyScreen {
                ZStack {
                    RoundedRectangle(cornerRadius: CGFloat(settings.borderRadius))
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: CGFloat(settings.borderRadius))
                        .fill(Color.black.opacity(0.4))
                    VStack(spacing: 4) {
                        Image(systemName: "eye.slash.fill")
                            .font(.system(size: 22, weight: .medium))
                        Text("Sharing is paused")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                }
                .frame(width: region.width, height: region.height)
                .position(x: region.midX, y: region.midY)
            } else {
                // Freeze: content looks unchanged; hint with a badge.
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.9), .black.opacity(0.55))
                    .position(x: region.maxX - 16, y: region.minY + 16)
            }
        }
    }

    private var notificationBanner: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.blue.opacity(0.8))
                .frame(width: 14, height: 14)
            VStack(alignment: .leading, spacing: 3) {
                Capsule().fill(Color.primary.opacity(0.5)).frame(width: 46, height: 3.5)
                Capsule().fill(Color.primary.opacity(0.25)).frame(width: 32, height: 3.5)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.white.opacity(0.2)))
    }

    private var miniHotbar: some View {
        HStack(spacing: 4.5) {
            ForEach(["line.3.horizontal", "stop.fill", "pause.fill", "record.circle",
                     "cursorarrow.rays", "arrow.up.left.and.arrow.down.right",
                     "plus.square.on.square", "scope", "xmark"], id: \.self) { symbol in
                Image(systemName: symbol)
                    .font(.system(size: 6.5, weight: .medium))
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.2)))
    }

    private func border(for region: CGRect) -> some View {
        let thickness = CGFloat(settings.borderThickness)
        let outset = thickness / 2 + 1
        let radius = settings.borderRadius > 0 ? CGFloat(settings.borderRadius) + outset : 0
        let dash: [CGFloat]
        var cap: CGLineCap = .butt
        switch settings.borderStyle {
        case .solid:
            dash = []
        case .dashed:
            dash = [thickness * 3, thickness * 2]
        case .dotted:
            dash = [0.01, thickness * 2.2]
            cap = .round
        }
        return RoundedRectangle(cornerRadius: radius)
            .strokeBorder(Color(nsColor: settings.borderColor),
                          style: StrokeStyle(lineWidth: thickness, lineCap: cap, dash: dash))
            .frame(width: region.width + outset * 2, height: region.height + outset * 2)
            .position(x: region.midX, y: region.midY)
    }
}

/// Even-odd "everything except the region" shape.
private struct DimShape: Shape {
    let cutout: CGRect
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        path.addRoundedRect(in: cutout, cornerSize: CGSize(width: cornerRadius,
                                                          height: cornerRadius))
        return path
    }
}

/// One expanding, fading ring; replayed by re-creating the view via .id().
private struct RippleDot: View {
    let color: Color
    @State private var animate = false

    var body: some View {
        Circle()
            .strokeBorder(color, lineWidth: 2)
            .scaleEffect(animate ? 1.35 : 0.3)
            .opacity(animate ? 0 : 1)
            .onAppear {
                withAnimation(.easeOut(duration: 0.5)) {
                    animate = true
                }
            }
    }
}
