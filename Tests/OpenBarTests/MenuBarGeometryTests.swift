import XCTest
import AppKit
import ApplicationServices
@testable import OpenBar

final class MenuBarGeometryTests: XCTestCase {
    @MainActor func testUnsupportedMenuBarArchitectureDoesNotPretendToHide() async {
        XCTAssertTrue(MenuBarGeometry.supportsSpacerHiding(onMajorVersion: 14))
        XCTAssertTrue(MenuBarGeometry.supportsSpacerHiding(onMajorVersion: 26))
        XCTAssertFalse(MenuBarGeometry.supportsSpacerHiding(onMajorVersion: 27))
        XCTAssertFalse(MenuBarGeometry.supportsSpacerHiding(onMajorVersion: 28))
        XCTAssertFalse(MenuBarGeometry.supportsSpacerHiding(onMajorVersion: 13))
        XCTAssertNil(OpenBarError.installRequired.settingsURL)
    }
    @MainActor func testTrayBoundariesExcludeAlwaysHiddenAndControl() async {
        XCTAssertFalse(MenuBarGeometry.isInTray(itemMidX: 199.99, leftBoundaryX: 200, rightBoundaryX: 400))
        XCTAssertTrue(MenuBarGeometry.isInTray(itemMidX: 200, leftBoundaryX: 200, rightBoundaryX: 400))
        XCTAssertTrue(MenuBarGeometry.isInTray(itemMidX: 399.99, leftBoundaryX: 200, rightBoundaryX: 400))
        XCTAssertFalse(MenuBarGeometry.isInTray(itemMidX: 400, leftBoundaryX: 200, rightBoundaryX: 400))
        XCTAssertFalse(MenuBarGeometry.isInTray(itemMidX: 300, leftBoundaryX: 400, rightBoundaryX: 200))
    }

    @MainActor func testNegativeAndVerticalDisplayOffsets() async {
        let display = CGRect(x: -1920, y: -1080, width: 1920, height: 1080)
        let item = CGRect(x: -400, y: -1078, width: 24, height: 22)
        XCTAssertEqual(MenuBarGeometry.sourceRect(for: item, in: display), CGRect(x: 1520, y: 2, width: 24, height: 22))
    }

    @MainActor func testMissingAndInvalidControlFramesAreUnsafe() async {
        let screen = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        XCTAssertFalse(MenuBarGeometry.isFrameOnScreen(.zero, screen: screen))
        XCTAssertFalse(MenuBarGeometry.isFrameOnScreen(CGRect(x: 5000, y: 0, width: 22, height: 22), screen: screen))
        XCTAssertFalse(MenuBarGeometry.isFrameOnScreen(CGRect(x: CGFloat.nan, y: 0, width: 22, height: 22), screen: screen))
        XCTAssertTrue(MenuBarGeometry.isFrameOnScreen(CGRect(x: -100, y: 0, width: 22, height: 22), screen: screen))
    }

    @MainActor func testSpacerOvershootsSmallAndLargeDisplays() async {
        XCTAssertGreaterThanOrEqual(MenuBarGeometry.hiddenLength(forScreenWidth: 1024), 8000)
        XCTAssertGreaterThan(MenuBarGeometry.hiddenLength(forScreenWidth: 6016), 6016 * 3)
    }

    @MainActor func testPermissionErrorsHaveDistinctSettingsDestinations() async {
        XCTAssertTrue(OpenBarError.accessibilityPermission.settingsURL!.absoluteString.hasSuffix("Privacy_Accessibility"))
        XCTAssertTrue(OpenBarError.screenRecordingPermission.settingsURL!.absoluteString.hasSuffix("Privacy_ScreenCapture"))
        XCTAssertNil(OpenBarError.noHiddenItems.settingsURL)
    }

    @MainActor func testMissingAXValuesDoNotCrash() async {
        let element = AXUIElementCreateApplication(-1)
        XCTAssertNil(AccessibilityClient.frame(of: element))
        XCTAssertTrue(AccessibilityClient.children(of: element).isEmpty)
        XCTAssertNil(AccessibilityClient.elementAttribute(kAXExtrasMenuBarAttribute, of: element))
    }

    @MainActor func testTrayWrapsWithoutClippingAndKeepsAllTargets() async {
        _ = NSApplication.shared
        let items = (0..<13).map { index in
            HiddenItem(name: "Item \(index)", image: NSImage(size: NSSize(width: 24, height: 22)), element: AXUIElementCreateApplication(-1))
        }
        let (content, mapping) = TrayPopoverContent.make(items: items, target: NSObject(), action: #selector(NSResponder.selectAll(_:)))
        XCTAssertEqual(mapping.count, items.count)
        XCTAssertGreaterThan(content.preferredContentSize.height, 100)
        XCTAssertEqual(content.preferredContentSize.width, 320)
        XCTAssertLessThanOrEqual(content.preferredContentSize.height, 400)
    }
}
