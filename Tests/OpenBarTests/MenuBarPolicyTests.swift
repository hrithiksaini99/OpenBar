import XCTest
@testable import OpenBar

final class MenuBarPolicyTests: XCTestCase {
    func testNewApplicationsRemainVisible() {
        let allowed = MenuBarPolicy.allowedBundles(running: ["com.new.app", "com.existing.hidden"],
            zones: ["com.existing.hidden": .hidden], own: "internal.openbar.app")
        XCTAssertTrue(allowed.contains("com.new.app"))
        XCTAssertFalse(allowed.contains("com.existing.hidden"))
    }

    func testSystemComponentsCannotBeHiddenBySavedAssignments() {
        let system: Set<String> = ["com.apple.MenuBarAgent", "com.apple.controlcenter", "com.apple.systemuiserver"]
        let zones = Dictionary(uniqueKeysWithValues: system.map { ($0, MenuBarZone.excluded) })
        let allowed = MenuBarPolicy.allowedBundles(running: system, zones: zones, own: "internal.openbar.app")
        XCTAssertTrue(system.isSubset(of: allowed))
    }

    func testOwnApplicationIsAlwaysKeptIncludingMalformedSavedAssignment() {
        let own = "internal.openbar.app"
        let allowed = MenuBarPolicy.allowedBundles(running: [], zones: [own: .excluded], own: own)
        XCTAssertEqual(allowed, [own])
    }

    func testBothHiddenZonesAreOmittedWhilePinnedApplicationRemains() {
        let allowed = MenuBarPolicy.allowedBundles(running: ["com.tray", "com.excluded", "com.pinned"],
            zones: ["com.tray": .hidden, "com.excluded": .excluded, "com.pinned": .visible], own: "com.openbar")
        XCTAssertEqual(allowed, ["com.openbar", "com.pinned"])
    }

    func testTemporaryExposureDoesNotExposeOtherHiddenApplications() {
        let zones: [String: MenuBarZone] = ["com.selected": .hidden, "com.other": .hidden, "com.excluded": .excluded]
        let running: Set<String> = ["com.selected", "com.other", "com.excluded", "com.pinned"]
        let exposed = MenuBarPolicy.allowedBundles(running: running, zones: zones, own: "com.openbar",
                                                  temporarilyVisible: ["com.selected"])
        XCTAssertEqual(exposed, ["com.selected", "com.pinned", "com.openbar"])
        let restored = MenuBarPolicy.allowedBundles(running: running, zones: zones, own: "com.openbar")
        XCTAssertEqual(restored, ["com.pinned", "com.openbar"])
    }
}
