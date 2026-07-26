import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let session = ShareSession()
    private var statusBar: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBar = StatusBarController(session: session)
    }

    func applicationWillTerminate(_ notification: Notification) {
        session.stop()
    }
}
