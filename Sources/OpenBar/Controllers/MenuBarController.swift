import AppKit
import ApplicationServices

@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    let store = MenuBarStore()
    private let controlItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let spacerItem: NSStatusItem? = ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 27 ? NSStatusBar.system.statusItem(withLength: MenuBarGeometry.spacerVisibleLength) : nil
    private let alwaysHiddenMarker: NSStatusItem? = ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 27 ? NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength) : nil
    private let native = NativeVisibilityService()
    private let manager = ManagementWindow()
    private let permissions = PermissionManager()
    private let popover = NSPopover()
    private var itemsByButton: [ObjectIdentifier: HiddenItem] = [:]
    private var operationTask: Task<Void, Never>?
    private var interactionTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var operationID = 0
    private var suspended = false
    private var lastInteraction = Date.distantPast
    private var menuTracking = false
    private var shuttingDown = false
    private var retryPermission = false
    private var retryTrayAfterAccess = false
    private var cachedEntries: [MenuBarEntry] = []
    private var usesNative: Bool { ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 }

    override init() {
        super.init()
        controlItem.button?.target = self
        controlItem.button?.action = #selector(handleClick)
        controlItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        controlItem.button?.setAccessibilityIdentifier("OpenBarControl")
        spacerItem?.button?.title = "|"
        spacerItem?.button?.isEnabled = false
        alwaysHiddenMarker?.button?.title = "⚑"
        alwaysHiddenMarker?.button?.isEnabled = false
        popover.behavior = .transient
        popover.delegate = self
        store.onPolicyChange = { [weak self] in self?.policyDidChange() }
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(appDidBecomeActive), name: NSApplication.didBecomeActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(displaysDidChange), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        center.addObserver(self, selector: #selector(menuDidBegin), name: NSMenu.didBeginTrackingNotification, object: nil)
        center.addObserver(self, selector: #selector(menuDidEnd), name: NSMenu.didEndTrackingNotification, object: nil)
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspace.addObserver(self, selector: #selector(workspaceDidChange), name: name, object: nil)
        }
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification] {
            workspace.addObserver(self, selector: #selector(displaysDidChange), name: name, object: nil)
        }
        updateControlImage()
        refreshApps()
    }

    @objc private func handleClick() {
        if NSApp.currentEvent?.type == .rightMouseUp { showMenu(); return }
        guard !store.isBusy else { return }
        if popover.isShown { popover.performClose(nil); return }
        if store.isHidden { beginOperation { [self] in try await openTray() } }
        else { hideSelected() }
    }

    func hideSelected() {
        guard !store.isBusy else { return }
        if usesNative && store.hiddenCount == 0 { showManagement(); return }
        beginOperation { [self] in
            try await applyHiding()
            store.isHidden = true
            store.status = "\(store.hiddenCount) app\(store.hiddenCount == 1 ? "" : "s") hidden."
            startInteractionGuard()
            updateControlImage()
        }
    }

    private func applyHiding(temporarilyVisible: Set<String> = []) async throws {
        if usesNative {
            guard Bundle.main.bundleURL.path.hasPrefix("/Applications/") else { throw OpenBarError.installRequired }
            let resolved = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            guard resolved?.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL else { throw OpenBarError.installRequired }
            let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
            let allowed = MenuBarPolicy.allowedBundles(running: running, zones: store.zones,
                own: Bundle.main.bundleIdentifier ?? "internal.openbar.app", temporarilyVisible: temporarilyVisible)
            try await native.activate(allowing: allowed)
        } else {
            let width = NSScreen.screens.map(\.frame.width).max() ?? 4000
            spacerItem?.length = MenuBarGeometry.hiddenLength(forScreenWidth: width)
        }
        try await Task.sleep(for: .milliseconds(120))
        try Task.checkCancellation()
        guard isControlSafelyVisible() else { releaseHiding(); throw OpenBarError.unavailableLayout }
        suspended = false
        lastHideTime = Date()
    }

    @discardableResult private func releaseHiding() -> Bool {
        native.reveal()
        spacerItem?.length = MenuBarGeometry.spacerVisibleLength
        if let error = native.lastRestorationError {
            store.errorMessage = "macOS did not confirm restoration: \(error.localizedDescription). Choose Show All to retry, or quit OpenBar."
            return false
        }
        return true
    }

    private func isControlSafelyVisible() -> Bool {
        if usesNative {
            // macOS 27 renders status items in a remote scene. LaunchServices
            // identity + the own-app allow rule are the reliable recovery route.
            return controlItem.isVisible && controlItem.button != nil && Bundle.main.bundleURL.path.hasPrefix("/Applications/")
        }
        guard let window = controlItem.button?.window, window.isVisible, let screen = window.screen else { return false }
        return MenuBarGeometry.isFrameOnScreen(window.frame, screen: screen.frame)
    }

    private func beginOperation(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !store.isBusy, !shuttingDown else { return }
        store.isBusy = true
        store.errorMessage = nil
        operationID += 1
        let id = operationID
        operationTask = Task { [weak self] in
            guard let self else { return }
            defer { if id == operationID { store.isBusy = false; operationTask = nil } }
            do { try await operation() }
            catch is CancellationError { }
            catch {
                guard id == operationID else { return }
                releaseHiding()
                store.isHidden = false
                suspended = false
                updateControlImage()
                presentFailure(error)
            }
        }
    }

    private func openTray() async throws {
        do { try permissions.requireAccessibility() }
        catch { retryTrayAfterAccess = true; throw error }
        retryPermission = false
        releaseHiding()
        suspended = true
        try await Task.sleep(for: .milliseconds(180))
        let entries = try await MenuBarInventory.snapshot()
        cachedEntries = entries
        store.refresh(entries: entries)
        let trayEntries: [MenuBarEntry]
        if usesNative {
            let screenID = (controlItem.button?.window?.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
            var seen = Set<String>()
            trayEntries = entries.filter {
                ($0.bundleIdentifier.map { store.zone(for: $0) == .hidden } ?? false)
                && (screenID == nil || $0.displayID == screenID)
                && seen.insert($0.identifier).inserted
            }
        } else {
            guard let marker = alwaysHiddenMarker?.button?.window, let control = controlItem.button?.window,
                  marker.frame.maxX < control.frame.minX else { throw OpenBarError.unavailableLayout }
            let screenID = (control.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
            trayEntries = entries.filter {
                MenuBarGeometry.isInTray(itemMidX: $0.frame.midX, leftBoundaryX: marker.frame.maxX, rightBoundaryX: control.frame.minX)
                && (screenID == nil || $0.displayID == screenID)
            }
        }
        let items = try await StatusItemScanner.capture(entries: trayEntries, useScreenCapture: CGPreflightScreenCaptureAccess())
        try Task.checkCancellation()
        try await applyHiding()
        guard !items.isEmpty else { throw OpenBarError.noHiddenItems }
        showPopover(items: items)
    }

    private func showPopover(items: [HiddenItem]) {
        guard let button = controlItem.button else { return }
        let (content, mapping) = TrayPopoverContent.make(items: items, target: self, action: #selector(pressItem(_:)))
        itemsByButton = mapping
        popover.contentViewController = content
        popover.contentSize = content.preferredContentSize
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    @objc private func pressItem(_ sender: NSButton) {
        guard !store.isBusy, let item = itemsByButton[ObjectIdentifier(sender)] else { return }
        popover.performClose(nil)
        beginOperation { [self] in
            try permissions.requireAccessibility()
            if usesNative, let bundle = item.bundleIdentifier { try await applyHiding(temporarilyVisible: [bundle]) }
            else { releaseHiding() }
            try await Task.sleep(for: .milliseconds(180))
            guard let entry = try await StatusItemScanner.resolve(item) else { throw OpenBarError.itemUnavailable }
            let result = AXUIElementPerformAction(entry.element, kAXPressAction as CFString)
            if result != .success {
                guard let frame = AccessibilityClient.frame(of: entry.element), let displayID = entry.displayID,
                      StatusItemScanner.frameIsClickable(frame, displayID: displayID) else { throw OpenBarError.itemUnavailable }
                click(at: CGPoint(x: frame.midX, y: frame.midY))
            }
            // Never collapse a menu while the user is still using it. The old
            // fixed three-second timer could close a real app's open menu.
            suspended = true
            lastInteraction = Date()
            store.status = "Item opened. Hiding resumes after menu interaction."
        }
    }

    private func click(at point: CGPoint) {
        let source = CGEventSource(stateID: .hidSystemState)
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
            event?.flags = []
            event?.post(tap: .cghidEventTap)
        }
    }

    private var lastHideTime = Date.distantPast

    private func startInteractionGuard() {
        guard interactionTask == nil else { return }
        interactionTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                guard let self, !shuttingDown else { return }
                guard store.isHidden, !store.isBusy else { continue }
                let interacting = SystemInteractionGuard.isInteracting() || menuTracking
                if interacting {
                    lastInteraction = Date()
                    if (!suspended || native.isActive) && Date().timeIntervalSince(lastHideTime) > 1.5 {
                        let restored = releaseHiding()
                        suspended = true
                        store.status = restored ? "Temporarily shown while using the menu bar." : "Restoration needs attention."
                    }
                } else if suspended && Date().timeIntervalSince(lastInteraction) > 1.2 {
                    beginOperation { [self] in
                        try await applyHiding()
                        store.status = "\(store.hiddenCount) apps hidden."
                    }
                }
            }
        }
    }

    @objc private func workspaceDidChange() {
        // A just-launched app is not yet in the assertion's snapshot. Release
        // immediately, then rebuild from the new complete inventory.
        resetPolicyOperation()
        refreshApps()
    }

    private func policyDidChange() {
        resetPolicyOperation()
        updateControlImage()
    }

    private func resetPolicyOperation() {
        if store.isHidden || store.isBusy {
            operationID += 1
            operationTask?.cancel()
            operationTask = nil
            store.isBusy = false
            releaseHiding()
            suspended = true
            lastInteraction = Date()
        }
    }

    func refreshApps() {
        store.refresh(entries: cachedEntries)
        refreshTask?.cancel()
        guard AXIsProcessTrusted() else { return }
        refreshTask = Task { [weak self] in
            do {
                let entries = try await MenuBarInventory.snapshot()
                try Task.checkCancellation()
                guard let self else { return }
                cachedEntries = entries
                store.refresh(entries: entries)
            } catch { /* Discovery failure never removes app choices or hides anything. */ }
        }
    }

    @objc private func appDidBecomeActive() {
        refreshApps()
        if retryPermission && AXIsProcessTrusted() {
            retryPermission = false
            if retryTrayAfterAccess && !store.isBusy {
                retryTrayAfterAccess = false
                beginOperation { [self] in
                    try await applyHiding()
                    store.isHidden = true
                    startInteractionGuard()
                    updateControlImage()
                    try await openTray()
                }
            }
        }
    }
    @objc private func displaysDidChange() { showAll(); refreshApps() }
    @objc private func menuDidBegin() { menuTracking = true; if store.isHidden { releaseHiding(); suspended = true } }
    @objc private func menuDidEnd() { menuTracking = false; lastInteraction = Date() }

    @objc func showAll() {
        operationID += 1
        operationTask?.cancel()
        operationTask = nil
        interactionTask?.cancel()
        interactionTask = nil
        popover.performClose(nil)
        releaseHiding()
        store.isHidden = false
        store.isBusy = false
        suspended = false
        retryPermission = false
        retryTrayAfterAccess = false
        store.errorMessage = nil
        store.status = "All menu bar items are visible."
        if let error = native.lastRestorationError { store.errorMessage = "Restoration needs a retry: \(error.localizedDescription). Quit OpenBar to release the restriction completely." }
        updateControlImage()
    }

    @objc func showManagement() {
        showAll()
        refreshApps()
        manager.show(store: store, onHide: { [weak self] in self?.hideSelected() }, onShowAll: { [weak self] in self?.showAll() },
            onOpenTray: { [weak self] in self?.openManagedTray() },
            onRefresh: { [weak self] in self?.refreshApps() }, onAccessibility: { [weak self] in self?.requestAccessibility() },
            onScreenCapture: { [weak self] in self?.requestScreenCapture() })
    }

    private func openManagedTray() {
        guard store.isHidden, !store.isBusy else { return }
        beginOperation { [self] in try await openTray() }
    }

    private func requestAccessibility() {
        if AXIsProcessTrusted() { NSWorkspace.shared.open(OpenBarError.accessibilityPermission.settingsURL!); return }
        do { try permissions.requireAccessibility(); refreshApps() }
        catch { presentFailure(error) }
    }
    private func requestScreenCapture() {
        if CGPreflightScreenCaptureAccess() { NSWorkspace.shared.open(OpenBarError.screenRecordingPermission.settingsURL!); return }
        do { try permissions.requireScreenCapture(); refreshApps() }
        catch { presentFailure(error) }
    }
    private func presentFailure(_ error: Error) {
        store.errorMessage = error.localizedDescription
        if let permission = error as? OpenBarError, let url = permission.settingsURL {
            retryPermission = true
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Enable OpenBar’s tray controls"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Not Now")
            if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(url) }
        } else if !manager.isVisible, let button = controlItem.button {
            popover.contentViewController = TrayPopoverContent.message(error.localizedDescription)
            popover.contentSize = NSSize(width: 320, height: 116)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func updateControlImage() {
        let image = NSImage(systemSymbolName: store.isHidden ? "tray.full" : "tray", accessibilityDescription: nil)
        image?.isTemplate = true
        controlItem.button?.image = image
        controlItem.button?.toolTip = store.isHidden ? "OpenBar: open hidden items. Right-click for Show All." : "OpenBar: hide selected apps. Right-click to manage."
        controlItem.button?.setAccessibilityLabel(store.isHidden ? "OpenBar, open hidden items" : "OpenBar, hide selected apps")
    }
    private func showMenu() {
        let menu = NSMenu()
        for (title, action) in [("Show All", #selector(showAll)), ("Manage Menu Bar…", #selector(showManagement))] {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: ""); item.target = self
        }
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: "Quit OpenBar", action: #selector(quit), keyEquivalent: "q"); quit.target = self
        controlItem.menu = menu
        controlItem.button?.performClick(nil)
        controlItem.menu = nil
    }
    @objc private func quit() { NSApp.terminate(nil) }
    func popoverDidClose(_ notification: Notification) { itemsByButton.removeAll() }
    func shutdown() {
        shuttingDown = true
        showAll()
        refreshTask?.cancel()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        for item in [controlItem, spacerItem, alwaysHiddenMarker].compactMap({ $0 }) { NSStatusBar.system.removeStatusItem(item) }
    }

    #if DEBUG
    func runSmokeCheck() async throws -> [String] {
        func stage(_ name: String) {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let timestamp = formatter.string(from: Date())
            let line = "STAGE: \(timestamp) \(name)\n"
            FileHandle.standardOutput.write(Data(line.utf8))
        }
        try await Task.sleep(for: .milliseconds(300))
        guard native.isAvailable else { throw NativeVisibilityError.unavailable }
        // Keep every running app and system control visible while exercising the
        // real private service. No user's preferences or permissions are changed.
        var allowed = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        allowed.formUnion([
            "com.apple.controlcenter",
            "com.apple.wifi.WiFiAgent",
            "com.apple.TextInputMenuAgent",
            "com.apple.Spotlight",
            "com.apple.systemuiserver",
            "com.apple.AccessibilityVisualsAgent",
            "com.apple.AccessibilityUIServer",
            "com.apple.menubarextra.bluetooth",
            "com.apple.menubarextra.wifi",
            "com.apple.menubarextra.battery",
            "com.apple.menubarextra.clock",
            "com.anthropic.claudefordesktop",
            "com.openai.codex"
        ])
        func diagnosticSnapshot(_ phase: String, comparingTo baseline: Set<String>? = nil) async throws -> Set<String> {
            let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
            if let windowListInfo = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] {
                for info in windowListInfo {
                    let layer = info[kCGWindowLayer as String] as? Int ?? 0
                    if layer == 25 || layer == 24 { // kCGStatusWindowLevel or kCGMainMenuWindowLevel
                        let name = info[kCGWindowName as String] as? String ?? "<no-name>"
                        let owner = info[kCGWindowOwnerName as String] as? String ?? "<no-owner>"
                        let pid = info[kCGWindowOwnerPID as String] as? Int ?? 0
                        let bounds = info[kCGWindowBounds as String] as? [String: Any]
                        let line = "CG-WINDOW [\(phase)]: Owner: \(owner) (PID: \(pid)), Window: \(name), Layer: \(layer), Bounds: \(bounds?.description ?? "nil")\n"
                        FileHandle.standardOutput.write(Data(line.utf8))
                    }
                }
            }
            guard AXIsProcessTrusted() else {
                stage("ax-unavailable-\(phase)")
                return []
            }
            let entries = try await MenuBarInventory.snapshot(includingOwnItems: true)
            let sorted = entries.sorted {
                let left = "\($0.bundleIdentifier ?? ""):\($0.name):\($0.frame.minX)"
                let right = "\($1.bundleIdentifier ?? ""):\($1.name):\($1.frame.minX)"
                return left < right
            }
            let identities = Set(entries.map(\.identifier))
            for entry in sorted {
                let owner = NSRunningApplication(processIdentifier: entry.processIdentifier)
                let resolved = entry.bundleIdentifier.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
                let values: [String: Any] = [
                    "phase": phase,
                    "identity": entry.identifier,
                    "bundle": entry.bundleIdentifier ?? "<missing>",
                    "name": entry.name,
                    "pid": entry.processIdentifier,
                    "frame": [entry.frame.minX, entry.frame.minY, entry.frame.width, entry.frame.height],
                    "runningAllowListContainsOwner": entry.bundleIdentifier.map { allowed.contains($0) } ?? false,
                    "runningBundleURL": owner?.bundleURL?.path ?? "<missing>",
                    "launchServicesURL": resolved?.path ?? "<missing>"
                ]
                let data = try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])
                FileHandle.standardOutput.write(Data("AX-ITEM: ".utf8) + data + Data("\n".utf8))
            }
            let candidates = Set(entries.compactMap(\.bundleIdentifier)).subtracting(allowed).sorted()
            let missing = baseline.map { $0.subtracting(identities).sorted() } ?? []
            let values: [String: Any] = ["phase": phase, "count": entries.count,
                "candidateBundleIDsOutsideRunningAllowList": candidates,
                "missingBaselineIdentities": missing]
            let data = try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])
            FileHandle.standardOutput.write(Data("AX-SUMMARY: ".utf8) + data + Data("\n".utf8))
            return identities
        }
        var results = ["macOS 27 native API is available"]
        if let option = CommandLine.arguments.firstIndex(of: "--smoke-hidden-bundle") {
            guard CommandLine.arguments.indices.contains(option + 1),
                  CommandLine.arguments[option + 1] == "internal.openbar.probe",
                  allowed.contains("internal.openbar.probe") else {
                throw NSError(domain: "OpenBar.SmokeCheck", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Selective smoke testing requires the disposable internal.openbar.probe fixture."])
            }
            defer { native.reveal() }
            stage("probe-visible")
            try await Task.sleep(for: .seconds(2))
            let baseline = try await diagnosticSnapshot("visible")
            stage("probe-hide-begin")
            try await native.activate(allowing: allowed.subtracting(["internal.openbar.probe"]))
            guard native.isActive else { throw NativeVisibilityError.unavailable }
            stage("probe-hidden")
            try await Task.sleep(for: .seconds(2))
            _ = try await diagnosticSnapshot("selective-hidden", comparingTo: baseline)
            stage("probe-restore-begin")
            native.reveal()
            guard !native.isActive else { throw native.lastRestorationError ?? NativeVisibilityError.unavailable }
            stage("probe-restored")
            try await Task.sleep(for: .seconds(2))
            _ = try await diagnosticSnapshot("restored", comparingTo: baseline)
            stage("probe-complete")
            stage("full-allow-begin")
            try await native.activate(allowing: allowed)
            guard native.isActive else { throw NativeVisibilityError.unavailable }
            stage("full-allow-active")
            try await Task.sleep(for: .seconds(2))
            _ = try await diagnosticSnapshot("full-allow", comparingTo: baseline)
            native.reveal()
            guard !native.isActive else { throw native.lastRestorationError ?? NativeVisibilityError.unavailable }
            stage("full-allow-restored")
            results.append("selective fixture activation and restoration completed; visual hiding needs a separate oracle")
        }
        stage("cycle-tests-begin")
        for _ in 0..<5 {
            try await native.activate(allowing: allowed)
            guard native.isActive else { throw NativeVisibilityError.unavailable }
            native.reveal()
            guard !native.isActive else { throw native.lastRestorationError ?? NativeVisibilityError.unavailable }
        }
        for _ in 0..<10 {
            let task = Task { try await native.activate(allowing: allowed) }
            await Task.yield()
            native.reveal()
            task.cancel()
            _ = try? await task.value
        }
        try await Task.sleep(for: .milliseconds(300))
        native.reveal()
        guard !native.isActive else { throw NativeVisibilityError.unavailable }
        stage("cycle-tests-complete")
        return results + ["5 real activation/restoration cycles completed", "10 cancellation cycles leave no active assertion", "all other running apps and 256 system identifiers were allowed", "no permission or saved-rule changes were made"]
    }
    #endif
}
