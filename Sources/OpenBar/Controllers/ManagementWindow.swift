import AppKit
import SwiftUI

@MainActor
final class ManagementWindow {
    private var window: NSWindow?

    var isVisible: Bool { window?.isVisible == true }

    func show(store: MenuBarStore, onHide: @escaping () -> Void, onShowAll: @escaping () -> Void,
              onOpenTray: @escaping () -> Void, onRefresh: @escaping () -> Void, onAccessibility: @escaping () -> Void, onScreenCapture: @escaping () -> Void) {
        if window == nil {
            let content = ManagementView(store: store, onHide: onHide, onShowAll: onShowAll, onOpenTray: onOpenTray, onRefresh: onRefresh,
                                         onAccessibility: onAccessibility, onScreenCapture: onScreenCapture)
            let host = NSHostingController(rootView: content)
            let window = NSWindow(contentViewController: host)
            window.title = "OpenBar"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 680, height: 630))
            window.minSize = NSSize(width: 620, height: 590)
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("OpenBarManagementWindow")
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
