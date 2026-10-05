import AppKit
import ApplicationServices
import ScreenCaptureKit

@MainActor
enum StatusItemScanner {
    static func scanInTray(between left: CGFloat, and right: CGFloat, on screen: NSScreen?) async throws -> [HiddenItem] {
        let entries = try await MenuBarInventory.snapshot()
        let screenID = (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        return try await capture(entries: entries.filter {
            MenuBarGeometry.isInTray(itemMidX: $0.frame.midX, leftBoundaryX: left, rightBoundaryX: right)
                && (screenID == nil || $0.displayID == screenID)
        })
    }

    /// Call with a snapshot of the revealed bar. Capture is optional, and a
    /// missing screen permission, notch, or disappeared window never drops an
    /// otherwise usable item from the tray or triggers a permission prompt.
    static func capture(entries: [MenuBarEntry], useScreenCapture: Bool = true) async throws -> [HiddenItem] {
        try Task.checkCancellation()
        var content: SCShareableContent?
        if useScreenCapture && CGPreflightScreenCaptureAccess() {
            do {
                content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            } catch {
                try Task.checkCancellation()
                // AX identity remains usable if screen enumeration fails.
            }
        }
        var items: [HiddenItem] = []
        for entry in entries {
            try Task.checkCancellation()
            var image: NSImage?
            if let content, let display = content.displays.first(where: { $0.displayID == entry.displayID }),
               captureIsSafe(frame: entry.frame, display: display) {
                image = await captureImage(frame: entry.frame, from: display)
                try Task.checkCancellation()
            }
            let imageIsFallback = image == nil
            let fallback = entry.appIcon
                ?? NSImage(systemSymbolName: "menubar.rectangle", accessibilityDescription: entry.name)
                ?? NSImage(size: NSSize(width: 24, height: 24))
            items.append(HiddenItem(name: entry.name, image: image ?? fallback, element: entry.element,
                identifier: entry.identifier, bundleIdentifier: entry.bundleIdentifier,
                processIdentifier: entry.processIdentifier, frame: entry.frame,
                displayID: entry.displayID, imageIsFallback: imageIsFallback))
        }
        return items // Inventory preserves physical menu-bar order per display.
    }

    /// Status-item AX handles can be invalidated when macOS reconstructs a
    /// remote menu scene. Re-resolve after revealing, before every press/click.
    static func resolve(_ item: HiddenItem) async throws -> MenuBarEntry? {
        let entries = try await MenuBarInventory.snapshot()
        if let exact = entries.first(where: { $0.identifier == item.identifier }) { return exact }
        let candidates = entries.filter {
            $0.bundleIdentifier == item.bundleIdentifier && $0.name == item.name
                && (item.bundleIdentifier != nil || $0.processIdentifier == item.processIdentifier)
        }
        return candidates.min { left, right in
            distance(left.frame, item.frame) < distance(right.frame, item.frame)
        }
    }

    private static func distance(_ left: CGRect, _ right: CGRect) -> CGFloat {
        abs(left.midX - right.midX) + abs(left.midY - right.midY)
    }

    private static func captureIsSafe(frame: CGRect, display: SCDisplay) -> Bool {
        frameIsClickable(frame, displayID: display.displayID)
    }

    static func frameIsClickable(_ frame: CGRect, displayID: CGDirectDisplayID) -> Bool {
        let bounds = CGDisplayBounds(displayID)
        guard bounds.contains(frame), frame.width > 0, frame.height > 0 else { return false }
        guard let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
        }), screen.safeAreaInsets.top > 0,
        let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else { return true }
        // The notch has no pixels representing a status icon. Show the app's
        // icon instead of capturing a black rectangle or part of the wallpaper.
        let notch = CGRect(x: left.maxX, y: bounds.minY,
                           width: max(0, right.minX - left.maxX), height: screen.safeAreaInsets.top)
        return !frame.intersects(notch)
    }

    private static func captureImage(frame: CGRect, from display: SCDisplay) async -> NSImage? {
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = MenuBarGeometry.sourceRect(for: frame, in: display.frame)
        let scale = CGFloat(CGDisplayPixelsWide(display.displayID)) / display.frame.width
        configuration.width = max(1, Int((frame.width * scale).rounded()))
        configuration.height = max(1, Int((frame.height * scale).rounded()))
        configuration.showsCursor = false
        let filter = SCContentFilter(display: display, excludingWindows: [])
        do {
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            return NSImage(cgImage: image, size: frame.size)
        } catch {
            return nil
        }
    }
}
