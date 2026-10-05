import AppKit

@MainActor
enum SystemInteractionGuard {
    static func isInteracting() -> Bool {
        if NSEvent.pressedMouseButtons != 0 { return true }
        let point = NSEvent.mouseLocation
        if NSScreen.screens.contains(where: { $0.frame.contains(point) && point.y >= $0.frame.maxY - 40 }) { return true }
        // Menu dropdowns and system panels can stay open after the pointer has
        // left the bar. Reading window geometry requires no capture permission.
        return false
    }
}
