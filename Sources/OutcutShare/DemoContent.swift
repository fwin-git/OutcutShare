import AppKit
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
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            bubble("Demo starts in 5 — everyone ready?", mine: false)
            bubble("Screen's set up 👍", mine: true)
            bubble("Remember: share only the monitor.", mine: false)
            bubble("That's the whole point 😄", mine: true)
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
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
