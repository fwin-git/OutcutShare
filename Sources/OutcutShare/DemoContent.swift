import AppKit
import IOSurface
import SwiftUI

/// The demo helper process: `--demo-windows=x,y,w,h` spawns three styled
/// fake app windows inside the stage and idles. Run as a SEPARATE process
/// (the app relaunching its own binary) so the drag machinery — which
/// deliberately ignores our own PID — treats them like any other app, and
/// the demos exercise the real cross-app Accessibility path. All content
/// is invented; nothing personal can appear in a recording.
@MainActor
final class DemoContentWindows {
    private var windows: [NSWindow] = []

    init(stage: CGRect) {
        let frames = Geometry.demoWindowFrames(stage: stage)
        let builders: [(String, AnyView)] = [
            ("Notes — Launch plan", AnyView(DemoNotesView())),
            ("Metrics", AnyView(DemoMetricsView())),
            ("Team Chat", AnyView(DemoChatView())),
        ]
        for (index, frame) in frames.enumerated() {
            let (title, view) = builders[index % builders.count]
            // .resizable matters: macOS silently rejects AX size changes on
            // non-resizable windows, which no-oped the grid resize on film.
            let window = NSWindow(contentRect: frame,
                                  styleMask: [.titled, .closable, .miniaturizable,
                                              .resizable],
                                  backing: .buffered, defer: false)
            window.title = title
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: view)
            window.setFrame(frame, display: true)
            window.orderFrontRegardless()
            windows.append(window)
        }
    }
}

/// Mock video-call window (Meet-style) shown by the DIRECTOR process: a
/// participant column plus a big "presentation" area that mirrors the live
/// capture — so the recording shows exactly what viewers of the share see.
/// Being our own window it is excluded from the session capture, so no
/// mirror tunnel.
@MainActor
final class DemoMeetMock {
    private let window: NSWindow
    private nonisolated(unsafe) let mirrorLayer = CALayer()

    init(frame: CGRect) {
        window = NSWindow(contentRect: frame,
                          styleMask: [.titled, .closable, .miniaturizable],
                          backing: .buffered, defer: false)
        window.title = "Weekly Sync — Video Call"
        window.isReleasedWhenClosed = false
        let view = NSView(frame: CGRect(origin: .zero, size: frame.size))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(calibratedRed: 0.11, green: 0.11,
                                              blue: 0.13, alpha: 1).cgColor
        let b = view.bounds
        let pad: CGFloat = 12
        let columnWidth = max(120, b.width * 0.22)

        // Presentation area: 16:9, mirroring the shared output.
        let mirrorFrame = CGRect(x: pad, y: pad,
                                 width: b.width - columnWidth - pad * 3,
                                 height: b.height - pad * 2 - 30)
        mirrorLayer.frame = mirrorFrame
        mirrorLayer.backgroundColor = NSColor.black.cgColor
        mirrorLayer.cornerRadius = 8
        mirrorLayer.masksToBounds = true
        mirrorLayer.contentsGravity = .resizeAspect
        view.layer?.addSublayer(mirrorLayer)

        let pill = CATextLayer()
        pill.string = "  You are presenting to everyone  "
        pill.fontSize = 12
        pill.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        pill.foregroundColor = NSColor.white.cgColor
        pill.backgroundColor = NSColor.systemBlue.cgColor
        pill.cornerRadius = 11
        pill.alignmentMode = .center
        pill.contentsScale = 2
        pill.frame = CGRect(x: mirrorFrame.midX - 110, y: mirrorFrame.maxY + 5,
                            width: 220, height: 22)
        view.layer?.addSublayer(pill)

        // Participant tiles.
        let people: [(String, String, NSColor)] = [
            ("A", "Ava", .systemTeal), ("J", "Jonas", .systemIndigo),
            ("M", "Mira", .systemOrange), ("You", "You", .systemGray),
        ]
        let tileHeight = (b.height - pad * 2 - CGFloat(people.count - 1) * 8)
            / CGFloat(people.count)
        for (index, person) in people.enumerated() {
            let tile = CALayer()
            tile.frame = CGRect(x: b.maxX - columnWidth - pad,
                                y: b.maxY - pad - CGFloat(index + 1) * tileHeight
                                    - CGFloat(index) * 8,
                                width: columnWidth, height: tileHeight)
            tile.backgroundColor = NSColor(calibratedWhite: 0.18, alpha: 1).cgColor
            tile.cornerRadius = 8
            let circle = CALayer()
            let diameter = min(44, tileHeight * 0.5)
            circle.frame = CGRect(x: (columnWidth - diameter) / 2,
                                  y: tileHeight / 2 - diameter / 2 + 8,
                                  width: diameter, height: diameter)
            circle.backgroundColor = person.2.cgColor
            circle.cornerRadius = diameter / 2
            tile.addSublayer(circle)
            let initial = CATextLayer()
            initial.string = person.0
            initial.fontSize = person.0.count > 1 ? 12 : 18
            initial.font = NSFont.systemFont(ofSize: 18, weight: .bold)
            initial.foregroundColor = NSColor.white.cgColor
            initial.alignmentMode = .center
            initial.contentsScale = 2
            initial.frame = CGRect(x: circle.frame.minX,
                                   y: circle.frame.midY - 9,
                                   width: diameter, height: 20)
            tile.addSublayer(initial)
            let name = CATextLayer()
            name.string = person.1
            name.fontSize = 11
            name.font = NSFont.systemFont(ofSize: 11, weight: .medium)
            name.foregroundColor = NSColor(calibratedWhite: 0.85, alpha: 1).cgColor
            name.alignmentMode = .center
            name.contentsScale = 2
            name.frame = CGRect(x: 0, y: 10, width: columnWidth, height: 15)
            tile.addSublayer(name)
            view.layer?.addSublayer(tile)
        }

        window.contentView = view
        window.setFrame(frame, display: true)
        window.orderFrontRegardless()
    }

    /// Fed from the session's capture queue.
    nonisolated func display(surface: IOSurfaceRef) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        mirrorLayer.contents = surface
        CATransaction.commit()
    }

    /// Live-selection mirroring: while the user still drags, the mirror
    /// shows a crop of the stage capture (nil = full frame again).
    func setCrop(_ unit: CGRect?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        mirrorLayer.contentsRect = unit ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        CATransaction.commit()
    }

    func close() {
        window.orderOut(nil)
    }
}

private struct DemoNotesView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Launch plan").font(.title2.bold())
            ForEach(["Ship the onboarding flow", "Refresh pricing page",
                     "Record feature walkthrough", "Draft release notes",
                     "Dry-run the live demo"], id: \.self) { line in
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.tint)
                    Text(line)
                }
                .font(.body)
            }
            Spacer()
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor))
    }
}

private struct DemoMetricsView: View {
    private let bars: [CGFloat] = [0.35, 0.55, 0.42, 0.7, 0.62, 0.88, 0.8]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Weekly active users").font(.headline)
            GeometryReader { proxy in
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(Array(bars.enumerated()), id: \.offset) { _, value in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(LinearGradient(colors: [.blue, .cyan],
                                                 startPoint: .bottom, endPoint: .top))
                            .frame(height: proxy.size.height * value)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
            Text("Mon  Tue  Wed  Thu  Fri  Sat  Sun")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct DemoChatView: View {
    /// A capture dragged out of the preview card lands here as a real
    /// cross-process file drop — the payoff shot of the capture demo.
    @State private var droppedImage: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            bubble("Demo starts in 5 — everyone ready?", mine: false)
            bubble("Screen's set up 👍", mine: true)
            bubble("Remember: share only the monitor.", mine: false)
            bubble("That's the whole point 😄", mine: true)
            if let image = droppedImage {
                HStack {
                    Spacer(minLength: 30)
                    Image(nsImage: image)
                        .resizable().scaledToFit()
                        .frame(maxWidth: 190)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first,
                  let image = NSImage(contentsOf: url) else { return false }
            droppedImage = image
            return true
        }
    }

    private func bubble(_ text: String, mine: Bool) -> some View {
        HStack {
            if mine { Spacer(minLength: 30) }
            Text(text)
                .font(.callout)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(mine ? Color.accentColor : Color.gray.opacity(0.25),
                            in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(mine ? Color.white : Color.primary)
            if !mine { Spacer(minLength: 30) }
        }
    }
}
