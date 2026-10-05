import AppKit
import Observation
import ApplicationServices

@MainActor
struct ManagedMenuApp: Identifiable {
    let id: String
    let name: String
    let icon: NSImage?
    let isRunning: Bool
    let itemCount: Int?
}

@MainActor @Observable
final class MenuBarStore {
    private(set) var apps: [ManagedMenuApp] = []
    private(set) var zones: [String: MenuBarZone] = [:]
    var isHidden = false
    var isBusy = false
    var accessibilityGranted = AXIsProcessTrusted()
    var screenCaptureGranted = CGPreflightScreenCaptureAccess()
    var status = "Choose which apps to hide."
    var errorMessage: String?
    var onPolicyChange: (() -> Void)?
    private let defaults: UserDefaults?
    private var knownNames: [String: String] = [:]
    private let key = "OpenBar.visibilityRules.v2"

    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        if let dictionary = defaults?.dictionary(forKey: key) as? [String: String] {
            zones = dictionary.compactMapValues(MenuBarZone.init(rawValue:))
        }
        knownNames = defaults?.dictionary(forKey: "OpenBar.knownAppNames.v2") as? [String: String] ?? [:]
    }

    var hiddenCount: Int { apps.filter { zone(for: $0.id) != .visible && $0.isRunning }.count }
    func zone(for bundle: String) -> MenuBarZone { zones[bundle] ?? .visible }
    func setZone(_ zone: MenuBarZone, for bundle: String) {
        guard !bundle.hasPrefix("com.apple."), bundle != Bundle.main.bundleIdentifier else { return }
        zones[bundle] = zone
        defaults?.set(zones.mapValues(\.rawValue), forKey: key)
        onPolicyChange?()
    }

    func refresh(entries: [MenuBarEntry] = []) {
        accessibilityGranted = AXIsProcessTrusted()
        screenCaptureGranted = CGPreflightScreenCaptureAccess()
        let own = Bundle.main.bundleIdentifier
        let running = NSWorkspace.shared.runningApplications.filter {
            !$0.isTerminated && $0.bundleIdentifier != own && $0.bundleIdentifier != nil
                && !($0.bundleIdentifier?.hasPrefix("com.apple.") ?? true)
                && ($0.activationPolicy == .regular || $0.activationPolicy == .accessory)
        }
        let counts = Dictionary(grouping: entries.compactMap(\.bundleIdentifier), by: { $0 }).mapValues(\.count)
        var rows: [String: ManagedMenuApp] = [:]
        for app in running {
            guard let bundle = app.bundleIdentifier else { continue }
            let name = app.localizedName ?? bundle
            knownNames[bundle] = name
            rows[bundle] = ManagedMenuApp(id: bundle, name: name, icon: app.icon, isRunning: true,
                                         itemCount: accessibilityGranted ? counts[bundle, default: 0] : nil)
        }
        for bundle in zones.keys where rows[bundle] == nil && zone(for: bundle) != .visible {
            rows[bundle] = ManagedMenuApp(id: bundle, name: knownNames[bundle] ?? bundle, icon: nil, isRunning: false, itemCount: nil)
        }
        apps = rows.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        defaults?.set(knownNames, forKey: "OpenBar.knownAppNames.v2")
    }
}
