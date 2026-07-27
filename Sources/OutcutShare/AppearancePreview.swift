import AppKit
import SwiftUI

/// Compact live rendering of the appearance options: a fake desktop with a
/// styled region, real dim contrast, cursor emphasis and looping click
/// ripples — all reacting to the settings as they change.
struct AppearancePreview: View {
    @ObservedObject var settings: SettingsStore
    @State private var rippleID = 0
    private let rippleTimer = Timer.publish(every: 1.7, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let region = CGRect(x: size.width * 0.18, y: size.height * 0.16,
                                width: size.width * 0.56, height: size.height * 0.62)
            let cursor = CGPoint(x: region.midX + region.width * 0.18,
                                 y: region.midY + region.height * 0.12)
            ZStack {
                desktop(size: size)
                if settings.dimmingEnabled {
                    DimShape(cutout: region, cornerRadius: cutoutRadius)
                        .fill(Color.black.opacity(settings.dimOpacity), style: FillStyle(eoFill: true))
                }
                if settings.showRegionBorder {
                    border(for: region)
                }
                if settings.clickRipples {
                    RippleDot(color: .yellow)
                        .frame(width: 44, height: 44)
                        .position(cursor)
                        .id(rippleID)
                }
                if settings.cursorHighlight {
                    Circle()
                        .fill(Color.yellow.opacity(0.28))
                        .overlay(Circle().strokeBorder(Color.yellow.opacity(0.85), lineWidth: 1.5))
                        .frame(width: 26, height: 26)
                        .position(cursor)
                }
                Image(nsImage: NSCursor.arrow.image)
                    .position(x: cursor.x + 5, y: cursor.y + 7)
            }
            .onReceive(rippleTimer) { _ in
                if settings.clickRipples {
                    rippleID += 1
                }
            }
        }
        .frame(height: 190)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
    }

    private var cutoutRadius: CGFloat { CGFloat(settings.borderRadius) }

    private func desktop(size: CGSize) -> some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.16, green: 0.22, blue: 0.42),
                                    Color(red: 0.45, green: 0.25, blue: 0.45)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            // Fake windows for depth.
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.82))
                .frame(width: size.width * 0.42, height: size.height * 0.5)
                .position(x: size.width * 0.34, y: size.height * 0.48)
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.9))
                .frame(width: size.width * 0.34, height: size.height * 0.42)
                .position(x: size.width * 0.68, y: size.height * 0.6)
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.white.opacity(0.25))
                .frame(width: size.width * 0.2, height: size.height * 0.22)
                .position(x: size.width * 0.82, y: size.height * 0.22)
        }
    }

    private func border(for region: CGRect) -> some View {
        let thickness = CGFloat(settings.borderThickness)
        let outset = thickness / 2 + 1
        let radius = cutoutRadius > 0 ? cutoutRadius + outset : 0
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
