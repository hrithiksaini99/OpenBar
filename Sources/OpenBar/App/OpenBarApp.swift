import AppKit

@main @MainActor
struct OpenBarApp {
    static func main() {
        if CommandLine.arguments.contains("--self-check") {
            SelfCheck.run()
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let bundle = Bundle.main.bundleIdentifier,
           let other = NSRunningApplication.runningApplications(withBundleIdentifier: bundle)
            .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            other.activate(options: [.activateAllWindows])
            NSApp.terminate(nil)
            return
        }
        controller = MenuBarController()
        #if DEBUG
        if CommandLine.arguments.contains("--smoke-check") {
            Task { [self] in
                do {
                    let results = try await controller!.runSmokeCheck()
                    for result in results { print("PASS: \(result)") }
                    print("OpenBar native smoke-check passed")
                    NSApp.terminate(nil)
                } catch {
                    print("OpenBar native smoke-check failed: \(error)")
                    controller?.shutdown()
                    exit(1)
                }
            }
            return
        }
        #endif
        controller?.showManagement()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller?.showManagement()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.shutdown()
    }
}
