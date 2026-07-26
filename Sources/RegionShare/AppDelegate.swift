import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let session = ShareSession()
    private var statusBar: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBar = StatusBarController(session: session)
        runShareTestIfRequested()
    }

    /// Debug mode: `--share-test=x,y,w,h,seconds` shares a fixed region of the
    /// main screen without the interactive selector, reports the frame count,
    /// then exits — used for automated end-to-end verification.
    private func runShareTestIfRequested() {
        guard let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--share-test=") }) else {
            return
        }
        let parts = arg.dropFirst("--share-test=".count).split(separator: ",").compactMap { Double($0) }
        guard parts.count == 5, let screen = NSScreen.main else {
            print("SHARE-TEST FAIL: usage --share-test=x,y,w,h,seconds")
            exit(2)
        }
        let rect = CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
        session.startSharing(rect: rect, on: screen)
        DispatchQueue.main.asyncAfter(deadline: .now() + parts[4]) { [session] in
            let frames = session.receivedFrameCount
            let active = session.isActive
            session.stop()
            print("SHARE-TEST \(active && frames > 0 ? "OK" : "FAIL") active=\(active) frames=\(frames)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                exit(active && frames > 0 ? 0 : 1)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        session.stop()
    }
}
