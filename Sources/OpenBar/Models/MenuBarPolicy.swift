import Foundation

enum MenuBarZone: String, CaseIterable, Identifiable, Codable, Sendable {
    case visible, hidden, excluded
    var id: String { rawValue }
    var title: String {
        switch self { case .visible: "Visible"; case .hidden: "In Tray"; case .excluded: "Hidden Only" }
    }
}

enum MenuBarPolicy {
    static func allowedBundles(running: Set<String>, zones: [String: MenuBarZone], own: String,
                               temporarilyVisible: Set<String> = []) -> Set<String> {
        // New applications and every system component stay visible by default.
        let hidden = Set(zones.filter { $0.value != .visible && !$0.key.hasPrefix("com.apple.") }.keys)
        return running.subtracting(hidden).union(temporarilyVisible).union([own])
    }
}
