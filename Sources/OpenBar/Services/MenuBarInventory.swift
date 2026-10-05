import AppKit
import ApplicationServices

/// The identity and geometry of one status item. Frames use Accessibility/Core
/// Graphics screen coordinates (top-left origin), never AppKit window frames.
@MainActor
struct MenuBarEntry {
    let identifier: String
    let name: String
    let bundleIdentifier: String?
    let processIdentifier: pid_t
    let element: AXUIElement
    let frame: CGRect
    let displayID: CGDirectDisplayID?
    let appIcon: NSImage?
}

@MainActor
enum MenuBarInventory {
    /// Accessibility discovery does not require Screen Recording and does not
    /// show any permission prompt. Hung applications have a bounded AX timeout.
    static func snapshot(includingOwnItems: Bool = false) async throws -> [MenuBarEntry] {
        try Task.checkCancellation()
        guard AXIsProcessTrusted() else { throw OpenBarError.accessibilityPermission }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let applications = NSWorkspace.shared.runningApplications.filter { app in
            !app.isTerminated && (includingOwnItems || app.processIdentifier != ownPID)
                && (app.bundleURL?.pathExtension == "app" || isSystemMenuHost(app.bundleIdentifier))
        }
        let descriptors = applications.map { InventoryApplication(
            pid: $0.processIdentifier, bundleIdentifier: $0.bundleIdentifier,
            name: $0.localizedName ?? "Menu bar item", isSystemHost: isSystemMenuHost($0.bundleIdentifier)) }
        let displays = NSScreen.screens.compactMap { screen -> InventoryDisplay? in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return InventoryDisplay(id: id.uint32Value, frame: CGDisplayBounds(id.uint32Value))
        }
        // AXUIElement is an immutable Core Foundation handle. Only the worker
        // accesses it during discovery; it transfers ownership back to the main
        // actor before interaction. AppKit objects stay on the main actor.
        let worker = Task.detached(priority: .userInitiated) {
            try InventoryWorker.read(applications: descriptors, displays: displays)
        }
        let records = try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
        try Task.checkCancellation()
        let icons = Dictionary(applications.map { ($0.processIdentifier, $0.icon) }, uniquingKeysWith: { first, _ in first })
        var occurrences: [String: Int] = [:]
        return records.map { record in
            let base = record.baseIdentifier
            let occurrence = occurrences[base, default: 0]
            occurrences[base] = occurrence + 1
            return MenuBarEntry(identifier: "\(base)#\(occurrence)", name: record.name,
                bundleIdentifier: record.bundleIdentifier, processIdentifier: record.pid,
                element: record.element, frame: record.frame, displayID: record.displayID,
                appIcon: icons[record.pid] ?? nil)
        }
    }

    /// macOS 27 hosts status-item views remotely; their NSWindow frame can be
    /// zero or refer to an unrelated window. Ask our own AX extras bar instead.
    /// A name is required when the application owns more than one visible item.
    static func ownFrame(pid: pid_t = ProcessInfo.processInfo.processIdentifier, named name: String? = nil) -> CGRect? {
        InventoryWorker.ownFrame(pid: pid, named: name)
    }

    /// Stable third-party owners are necessary for the native per-application
    /// hiding policy. System-owned controls are discoverable but stay pinned.
    static func isSystemOwned(_ entry: MenuBarEntry) -> Bool {
        guard let bundle = entry.bundleIdentifier else { return true }
        return bundle.hasPrefix("com.apple.")
    }

    private static func isSystemMenuHost(_ bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        let identifier = bundleIdentifier.lowercased()
        return identifier == "com.apple.controlcenter" || identifier == "com.apple.menubaragent" || identifier.contains("menubarscene")
            || identifier.contains("menubarnavigation") || identifier == "com.apple.systemuiserver"
    }
}

private struct InventoryApplication: Sendable {
    let pid: pid_t
    let bundleIdentifier: String?
    let name: String
    let isSystemHost: Bool
}

private struct InventoryDisplay: Sendable {
    let id: CGDirectDisplayID
    let frame: CGRect
}

// AX handles have immutable CF identity and support AX calls from a background
// thread. These records transfer those handles once, after discovery completes.
private struct InventoryRecord: @unchecked Sendable {
    let name: String
    let bundleIdentifier: String?
    let pid: pid_t
    let element: AXUIElement
    let frame: CGRect
    let displayID: CGDirectDisplayID?
    let baseIdentifier: String
}

private enum InventoryWorker {
    private static let timeout: Float = 0.1
    private static let maxElementsPerApplication = 256

    static func read(applications: [InventoryApplication], displays: [InventoryDisplay]) throws -> [InventoryRecord] {
        var records: [InventoryRecord] = []
        let clock = ContinuousClock()
        let totalDeadline = clock.now.advanced(by: .seconds(4))
        let applicationsByPID = Dictionary(applications.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        // The owning application's extras bar is authoritative. Hosted system
        // trees supplement it, and cannot replace a correct third-party owner.
        let ordered = applications.sorted { !$0.isSystemHost && $1.isSystemHost }
        for application in ordered {
            try Task.checkCancellation()
            guard clock.now < totalDeadline else { break }
            let budget = DiscoveryBudget(totalDeadline: totalDeadline,
                applicationDeadline: clock.now.advanced(by: .milliseconds(500)))
            let appElement = AXUIElementCreateApplication(application.pid)
            AXUIElementSetMessagingTimeout(appElement, timeout)
            var roots: [AXUIElement] = []
            if let extras = element(kAXExtrasMenuBarAttribute, of: appElement, budget: budget) { roots.append(extras) }
            if application.isSystemHost, let menu = element(kAXMenuBarAttribute, of: appElement, budget: budget) {
                if !roots.contains(where: { CFEqual($0, menu) }) { roots.append(menu) }
            }
            var visited: [AXUIElement] = []
            for root in roots {
                try walk(root, depth: 0, application: application, applications: applicationsByPID,
                         displays: displays, budget: budget, visited: &visited, records: &records)
            }
        }
        return records.sorted { lhs, rhs in
            if lhs.displayID != rhs.displayID {
                if lhs.frame.minY != rhs.frame.minY { return lhs.frame.minY < rhs.frame.minY }
                return (lhs.displayID ?? .max) < (rhs.displayID ?? .max)
            }
            if lhs.frame.minX != rhs.frame.minX { return lhs.frame.minX < rhs.frame.minX }
            return lhs.baseIdentifier < rhs.baseIdentifier
        }
    }

    private static func walk(_ node: AXUIElement, depth: Int, application: InventoryApplication,
                             applications: [pid_t: InventoryApplication], displays: [InventoryDisplay],
                             budget: DiscoveryBudget, visited: inout [AXUIElement], records: inout [InventoryRecord]) throws {
        try Task.checkCancellation()
        guard !budget.hasExpired, depth <= 4, visited.count < maxElementsPerApplication,
              !visited.contains(where: { CFEqual($0, node) }) else { return }
        visited.append(node)
        AXUIElementSetMessagingTimeout(node, timeout)
        let role = string(kAXRoleAttribute, of: node, budget: budget)
        // Some remote scene controls expose AXButton instead of AXMenuBarItem.
        // Such buttons count only within an extras/system menu-bar tree and the
        // menu-bar band, avoiding normal application menus and window controls.
        let itemRoles = [kAXMenuBarItemRole, kAXButtonRole, "AXStatusItem"]
        if depth > 0, let role, itemRoles.contains(role), let frame = frame(node, budget: budget),
           isInMenuBand(frame, displays: displays) {
            var pid: pid_t = application.pid
            if AXUIElementGetPid(node, &pid) != .success { pid = application.pid }
            let owner = applications[pid] ?? application
            let name = string(kAXDescriptionAttribute, of: node, budget: budget)
                ?? string(kAXTitleAttribute, of: node, budget: budget) ?? string(kAXHelpAttribute, of: node, budget: budget) ?? owner.name
            let display = displays.filter { $0.frame.intersects(frame) }.max {
                area($0.frame.intersection(frame)) < area($1.frame.intersection(frame))
            }
            let rawIdentifier = string(kAXIdentifierAttribute, of: node, budget: budget) ?? name
            let base = "\(owner.bundleIdentifier ?? "pid:\(owner.pid)"):\(rawIdentifier)"
            // Parent containers and remote host mirrors may report the same
            // icon. Prefer the first (own-app) record at matching geometry.
            let duplicate = records.contains { record in
                CFEqual(record.element, node) || (record.displayID == display?.id
                    && abs(record.frame.minX - frame.minX) < 0.5
                    && abs(record.frame.minY - frame.minY) < 0.5
                    && abs(record.frame.width - frame.width) < 0.5
                    && abs(record.frame.height - frame.height) < 0.5)
            }
            if !duplicate {
                records.append(InventoryRecord(name: name, bundleIdentifier: owner.bundleIdentifier,
                    pid: owner.pid, element: node, frame: frame, displayID: display?.id, baseIdentifier: base))
            }
            return // The children of a status item can be its open dropdown.
        }
        for child in children(node, budget: budget) {
            try walk(child, depth: depth + 1, application: application, applications: applications,
                     displays: displays, budget: budget, visited: &visited, records: &records)
        }
    }

    static func ownFrame(pid: pid_t, named name: String?) -> CGRect? {
        let deadline = ContinuousClock().now.advanced(by: .milliseconds(500))
        let budget = DiscoveryBudget(totalDeadline: deadline, applicationDeadline: deadline)
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, timeout)
        guard let root = element(kAXExtrasMenuBarAttribute, of: application, budget: budget) else { return nil }
        var visited: [AXUIElement] = []
        return findOwnFrame(root, named: name, depth: 0, budget: budget, visited: &visited)
    }

    private static func findOwnFrame(_ node: AXUIElement, named name: String?, depth: Int,
                                     budget: DiscoveryBudget, visited: inout [AXUIElement]) -> CGRect? {
        guard !budget.hasExpired, depth <= 4, visited.count < 64,
              !visited.contains(where: { CFEqual($0, node) }) else { return nil }
        visited.append(node)
        AXUIElementSetMessagingTimeout(node, timeout)
        if depth > 0 {
            var matches = name == nil
            if let name {
                matches = [kAXIdentifierAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute]
                    .contains { string($0, of: node, budget: budget) == name }
            }
            if matches, let frame = frame(node, budget: budget) { return frame }
        }
        for child in children(node, budget: budget) {
            if let frame = findOwnFrame(child, named: name, depth: depth + 1, budget: budget, visited: &visited) {
                return frame
            }
        }
        return nil
    }

    private static func isInMenuBand(_ frame: CGRect, displays: [InventoryDisplay]) -> Bool {
        frame.height <= 100 && displays.contains { display in
            frame.midY >= display.frame.minY - 1 && frame.midY < display.frame.minY + 100
        }
    }

    private static func area(_ frame: CGRect) -> CGFloat { frame.isNull ? 0 : frame.width * frame.height }

    private static func attribute(_ name: String, of element: AXUIElement, budget: DiscoveryBudget) -> CFTypeRef? {
        guard !budget.hasExpired else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func string(_ name: String, of element: AXUIElement, budget: DiscoveryBudget) -> String? {
        guard let value = attribute(name, of: element, budget: budget), CFGetTypeID(value) == CFStringGetTypeID() else { return nil }
        let result = (value as! String).trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    private static func element(_ name: String, of element: AXUIElement, budget: DiscoveryBudget) -> AXUIElement? {
        guard let value = attribute(name, of: element, budget: budget), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func children(_ element: AXUIElement, budget: DiscoveryBudget) -> [AXUIElement] {
        guard let value = attribute(kAXChildrenAttribute, of: element, budget: budget),
              CFGetTypeID(value) == CFArrayGetTypeID() else { return [] }
        return value as? [AXUIElement] ?? []
    }

    private static func frame(_ element: AXUIElement, budget: DiscoveryBudget) -> CGRect? {
        guard let position = attribute(kAXPositionAttribute, of: element, budget: budget),
              let dimensions = attribute(kAXSizeAttribute, of: element, budget: budget),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(dimensions) == AXValueGetTypeID() else { return nil }
        let pointValue = unsafeDowncast(position, to: AXValue.self)
        let sizeValue = unsafeDowncast(dimensions, to: AXValue.self)
        guard AXValueGetType(pointValue) == .cgPoint, AXValueGetType(sizeValue) == .cgSize else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(pointValue, .cgPoint, &point), AXValueGetValue(sizeValue, .cgSize, &size),
              point.x.isFinite, point.y.isFinite, size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0 else { return nil }
        return CGRect(origin: point, size: size)
    }
}

/// Monotonic deadlines bound each application and the whole discovery. A busy
/// app is skipped, and an exhausted overall budget returns the useful partial
/// inventory already collected. Each final in-flight AX call adds at most 0.1 s.
private struct DiscoveryBudget {
    let totalDeadline: ContinuousClock.Instant
    let applicationDeadline: ContinuousClock.Instant

    var hasExpired: Bool {
        let now = ContinuousClock().now
        return now >= totalDeadline || now >= applicationDeadline
    }
}
