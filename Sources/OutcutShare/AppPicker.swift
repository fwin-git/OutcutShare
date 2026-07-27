import AppKit
import SwiftUI

struct InstalledApp: Identifiable {
    let bundleID: String
    let name: String
    let url: URL

    var id: String { bundleID }
}

/// Scans the standard application folders once per picker opening.
enum AppCatalog {
    static func scan() -> [InstalledApp] {
        var seen = Set<String>()
        var result: [InstalledApp] = []
        let directories = ["/Applications", "/Applications/Utilities",
                           "/System/Applications", "/System/Applications/Utilities",
                           NSHomeDirectory() + "/Applications"]
        for directory in directories {
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: directory) else {
                continue
            }
            for entry in entries where entry.hasSuffix(".app") {
                let url = URL(fileURLWithPath: directory).appendingPathComponent(entry)
                guard let bundleID = Bundle(url: url)?.bundleIdentifier,
                      seen.insert(bundleID).inserted else {
                    continue
                }
                let name = FileManager.default.displayName(atPath: url.path)
                    .replacingOccurrences(of: ".app", with: "")
                result.append(InstalledApp(bundleID: bundleID, name: name, url: url))
            }
        }
        return result.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// Typically sensitive apps, surfaced first when installed.
    static let suggestedBundleIDs: Set<String> = [
        "com.apple.mail", "com.apple.MobileSMS", "com.apple.Notes",
        "com.apple.iCal", "com.apple.Passwords", "com.apple.FaceTime",
        "com.tinyspeck.slackmacgap", "com.hnc.Discord", "ru.keepcoder.Telegram",
        "org.whispersystems.signal-desktop", "net.whatsapp.WhatsApp",
        "com.microsoft.teams2", "com.1password.1password", "com.bitwarden.desktop",
    ]
}

/// Searchable list of installed apps for the hidden-apps privacy list.
struct AppPickerSheet: View {
    @ObservedObject var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var apps: [InstalledApp] = []

    private var filtered: [InstalledApp] {
        guard !query.isEmpty else { return apps }
        return apps.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.bundleID.localizedCaseInsensitiveContains(query)
        }
    }

    private var suggested: [InstalledApp] {
        filtered.filter { AppCatalog.suggestedBundleIDs.contains($0.bundleID) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search apps", text: $query)
                    .textFieldStyle(.plain)
            }
            .padding(10)
            Divider()
            List {
                if !suggested.isEmpty {
                    Section("Suggested") {
                        ForEach(suggested) { row(for: $0) }
                    }
                }
                Section(query.isEmpty ? "All apps" : "Results") {
                    ForEach(filtered) { row(for: $0) }
                }
            }
            .listStyle(.inset)
            Divider()
            HStack {
                Button("Browse…") { browse() }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(10)
        }
        .frame(width: 400, height: 480)
        .onAppear { apps = AppCatalog.scan() }
    }

    private func row(for app: InstalledApp) -> some View {
        let isHidden = settings.hiddenApps.contains { $0.bundleID == app.bundleID }
        return HStack {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                .resizable()
                .frame(width: 22, height: 22)
            Text(app.name)
            Spacer()
            Image(systemName: isHidden ? "checkmark.circle.fill" : "plus.circle")
                .foregroundStyle(isHidden ? Color.accentColor : Color.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isHidden {
                settings.hiddenApps.removeAll { $0.bundleID == app.bundleID }
            } else {
                settings.hiddenApps.append(HiddenApp(bundleID: app.bundleID, name: app.name))
            }
        }
    }

    /// Fallback for apps living outside the standard folders.
    private func browse() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bundleID = Bundle(url: url)?.bundleIdentifier,
                  !settings.hiddenApps.contains(where: { $0.bundleID == bundleID }) else {
                continue
            }
            let name = FileManager.default.displayName(atPath: url.path)
                .replacingOccurrences(of: ".app", with: "")
            settings.hiddenApps.append(HiddenApp(bundleID: bundleID, name: name))
        }
    }
}
