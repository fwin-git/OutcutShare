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
                      title: L10n.string(.permissionsScreenRecordingTitle),
                      detail: screenRecordingDetail)

            if !model.status.screenRecordingGranted {
                VStack(alignment: .leading, spacing: 6) {
                    Text(LocalizedStringKey(L10n.string(.permissionsGuide1)))
                    Text(LocalizedStringKey(L10n.string(.permissionsGuide2)))
                    Text(LocalizedStringKey(L10n.string(.permissionsGuide3)))
                }
                .font(.callout)
                .padding(.leading, 30)

                HStack {
                    Button(L10n.string(.permissionsRequest)) {
                        model.requestScreenRecording()
                    }
                        .keyboardShortcut(.defaultAction)
                    Button(L10n.string(.permissionsOpenSystemSettings)) {
                        model.openSystemSettings()
                    }
                }
                .padding(.leading, 30)
            } else if model.status.needsRelaunch {
                Button(L10n.string(.permissionsRelaunch)) { model.relaunch() }
                    .keyboardShortcut(.defaultAction)
                    .padding(.leading, 30)
            }

            statusRow(state: model.status.virtualDisplayAvailable ? .ok : .warning,
                      title: L10n.string(.permissionsVirtualDisplayTitle),
                      detail: model.status.virtualDisplayAvailable
                          ? L10n.string(.permissionsVirtualDisplayAvailable)
                          : L10n.string(.permissionsVirtualDisplayUnavailable))

            statusRow(state: model.status.accessibilityGranted ? .ok : .pending,
                      title: L10n.string(.permissionsAccessibilityTitle),
                      detail: model.status.accessibilityGranted
                          ? L10n.string(.permissionsAccessibilityGranted)
                          : L10n.string(.permissionsAccessibilityPending))
            if !model.status.accessibilityGranted {
                HStack {
                    Button(L10n.string(.permissionsRequest)) {
                        model.requestAccessibility()
                    }
                    Button(L10n.string(.permissionsOpenSystemSettings)) {
                        model.openAccessibilitySettings()
                    }
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
            return L10n.string(.permissionsScreenRecordingGranted)
        }
        if model.status.needsRelaunch {
            return L10n.string(.permissionsScreenRecordingRelaunch)
        }
        return L10n.string(.permissionsScreenRecordingRequired)
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
                    Text(L10n.string(.permissionsWelcome)).font(.title3).bold()
                    Text(model.status.allSatisfied
                         ? L10n.string(.permissionsAllInPlace)
                         : L10n.string(.permissionsOneNeeded))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            PermissionsStatusView(model: model)

            Divider()

            HStack {
                if model.status.allSatisfied {
                    Label(
                        L10n.string(.permissionsReady),
                        systemImage: "checkmark.seal.fill"
                    )
                        .foregroundStyle(.green)
                }
                Spacer()
                Button(
                    model.status.allSatisfied
                        ? L10n.string(.commonDone) : L10n.string(.commonLater)
                ) {
                    onDone()
                }
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
            window.title = L10n.string(.permissionsWindowTitle)
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
