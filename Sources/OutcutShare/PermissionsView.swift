import AppKit
import SwiftUI

/// The permission/health rows with live checkmarks, guide steps and action
/// buttons — reused by the standalone onboarding window and the Permissions
/// settings tab.
struct PermissionsStatusView: View {
    @ObservedObject var model: PermissionsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            statusRow(state: screenRecordingState,
                      title: "Screen & System Audio Recording",
                      detail: screenRecordingDetail)

            if !model.status.screenRecordingGranted {
                VStack(alignment: .leading, spacing: 6) {
                    Text("1.  Click **Request Permission** and choose *Allow* in the macOS dialog.")
                    Text("2.  No dialog? Enable **Outcut Share** in *System Settings → Privacy & Security → Screen & System Audio Recording*.")
                    Text("3.  Come back here — the checkmark updates by itself.")
                }
                .font(.callout)
                .padding(.leading, 30)

                HStack {
                    Button("Request Permission") { model.requestScreenRecording() }
                        .keyboardShortcut(.defaultAction)
                    Button("Open System Settings") { model.openSystemSettings() }
                }
                .padding(.leading, 30)
            } else if model.status.needsRelaunch {
                Button("Relaunch Outcut Share") { model.relaunch() }
                    .keyboardShortcut(.defaultAction)
                    .padding(.leading, 30)
            }

            statusRow(state: model.status.virtualDisplayAvailable ? .ok : .warning,
                      title: "Virtual display support",
                      detail: model.status.virtualDisplayAvailable
                          ? "Available — the region can appear as its own monitor."
                          : "Unavailable on this macOS — use the Hidden Window share mode.")

            statusRow(state: model.status.accessibilityGranted ? .ok : .pending,
                      title: "Accessibility (optional)",
                      detail: model.status.accessibilityGranted
                          ? "Granted — drag windows onto the virtual monitor's preview to move them there."
                          : "Lets you move windows onto the Virtual Monitor by dropping them on its preview.")
            if !model.status.accessibilityGranted {
                HStack {
                    Button("Request Permission") { model.requestAccessibility() }
                    Button("Open System Settings") { model.openAccessibilitySettings() }
                }
                .padding(.leading, 30)
            }
        }
    }

    private enum RowState { case ok, pending, warning }

    private var screenRecordingState: RowState {
        if model.status.captureWorks { return .ok }
        if model.status.needsRelaunch { return .warning }
        return .pending
    }

    private var screenRecordingDetail: String {
        if model.status.captureWorks {
            return "Granted."
        }
        if model.status.needsRelaunch {
            return "Granted — relaunch Outcut Share so it takes effect."
        }
        return "Required to capture the selected screen region."
    }

    private func statusRow(state: RowState, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                switch state {
                case .ok:
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                case .pending:
                    Image(systemName: "circle").foregroundStyle(.secondary)
                case .warning:
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
            }
            .font(.system(size: 20))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).bold()
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

struct PermissionsView: View {
    @ObservedObject var model: PermissionsModel
    var onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.dashed.badge.record")
                    .font(.system(size: 28))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading) {
                    Text("Welcome to Outcut Share").font(.title3).bold()
                    Text(model.status.allSatisfied
                         ? "All permissions are in place — nothing to do here."
                         : "One system permission is needed before you can share a region.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            PermissionsStatusView(model: model)

            Divider()

            HStack {
                if model.status.allSatisfied {
                    Label("All set — you're ready to share.", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                }
                Spacer()
                Button(model.status.allSatisfied ? "Done" : "Later") { onDone() }
            }
        }
        .padding(20)
        .frame(width: 470)
    }
}

@MainActor
final class PermissionsWindowController {
    let model = PermissionsModel()
    private var window: NSWindow?
    private var closeObserver: NSObjectProtocol?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: PermissionsView(model: model) { [weak self] in
                self?.window?.close()
            })
            let window = NSWindow(contentViewController: hosting)
            window.title = "Outcut Share Permissions"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
            closeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.model.stopPolling() }
            }
        }
        model.startPolling()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
