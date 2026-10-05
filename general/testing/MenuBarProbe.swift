import AppKit

/// Disposable status item used by the selective macOS 27 visibility smoke test.
/// It asks for no permission and exits automatically if its harness disappears.
@main @MainActor
struct MenuBarProbe {
    static func main() {
        let app = NSApplication.shared
        let delegate = ProbeDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
private final class ProbeDelegate: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem?
    private var expiry: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item?.button?.title = "◈OB◈"
        item?.button?.toolTip = "Disposable OpenBar visibility test fixture"
        item?.button?.setAccessibilityLabel("OpenBar visibility test fixture")
        item?.autosaveName = "OpenBarVisibilityProbe"
        if let flag = CommandLine.arguments.firstIndex(of: "--ready-file"),
           CommandLine.arguments.indices.contains(flag + 1) {
            let ready = "\(ProcessInfo.processInfo.processIdentifier)\n\(Bundle.main.bundleIdentifier ?? "unknown")\n"
            try? Data(ready.utf8).write(to: URL(fileURLWithPath: CommandLine.arguments[flag + 1]), options: .atomic)
        }
        expiry = Timer.scheduledTimer(withTimeInterval: 45, repeats: false) { _ in
            MainActor.assumeIsolated { NSApp.terminate(nil) }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        expiry?.invalidate()
        if let item { NSStatusBar.system.removeStatusItem(item) }
    }
}
