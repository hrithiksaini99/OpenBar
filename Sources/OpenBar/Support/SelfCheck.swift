import AppKit

@MainActor
enum SelfCheck {
    static func run() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        precondition(MenuBarGeometry.isFrameOnScreen(CGRect(x: 100, y: 0, width: 22, height: 22), screen: screen))
        precondition(!MenuBarGeometry.isFrameOnScreen(CGRect(x: 5000, y: 0, width: 22, height: 22), screen: screen))
        precondition(MenuBarGeometry.hiddenLength(forScreenWidth: 6016) > 6016 * 3)
        precondition(!MenuBarGeometry.isInTray(itemMidX: 100, leftBoundaryX: 200, rightBoundaryX: 400))
        precondition(MenuBarGeometry.isInTray(itemMidX: 300, leftBoundaryX: 200, rightBoundaryX: 400))
        for symbol in ["tray", "tray.full"] {
            precondition(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil, "Missing SF Symbol: \(symbol)")
        }
        precondition(MenuBarGeometry.sourceRect(for: CGRect(x: 3500, y: 2, width: 24, height: 22),
                                               in: CGRect(x: 1728, y: 0, width: 1920, height: 1080))
                     == CGRect(x: 1772, y: 2, width: 24, height: 22))
        print("OpenBar self-check passed")
    }
}
