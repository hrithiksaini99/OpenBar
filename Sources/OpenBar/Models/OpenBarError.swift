import Foundation

@MainActor
enum OpenBarError: LocalizedError {
    case accessibilityPermission
    case screenRecordingPermission
    case noHiddenItems
    case unavailableLayout
    case itemUnavailable
    case installRequired

    nonisolated var errorDescription: String? {
        switch self {
        case .accessibilityPermission:
            "OpenBar needs Accessibility access to find and press menu bar items. Grant it in System Settings, then relaunch OpenBar."
        case .screenRecordingPermission:
            "OpenBar needs Screen Recording access to show the exact current icon for each hidden item. Grant it in System Settings, then relaunch OpenBar."
        case .noHiddenItems:
            "No menu bar items were found for your tray apps. Use Manage Menu Bar to choose In Tray, refresh the app list, then try again. Some apps do not expose a usable menu bar item."
        case .unavailableLayout:
            "OpenBar could not safely hide items on this display. Choose Show All and try again from the installed copy in Applications."
        case .itemUnavailable:
            "This menu bar item is no longer available. Open the tray again to refresh it."
        case .installRequired:
            "Run the installed copy of OpenBar in Applications. macOS needs that stable app identity to keep OpenBar’s recovery icon visible while hiding other apps."
        }
    }

    var settingsURL: URL? {
        let pane: String
        switch self {
        case .accessibilityPermission: pane = "Privacy_Accessibility"
        case .screenRecordingPermission: pane = "Privacy_ScreenCapture"
        default: return nil
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")
    }
}
