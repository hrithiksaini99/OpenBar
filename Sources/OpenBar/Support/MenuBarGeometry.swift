import CoreGraphics
import Foundation

@MainActor
enum MenuBarGeometry {
    static let spacerVisibleLength: CGFloat = 8
    static let watchdogInterval: TimeInterval = 8
    static let verifyDelay: TimeInterval = 0.12
    static let revealSettleDelayMS: UInt64 = 180
    static let clickGraceSeconds: UInt64 = 3

    static func supportsSpacerHiding(onMajorVersion version: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion) -> Bool {
        (14..<27).contains(version)
    }

    static func hiddenLength(forScreenWidth width: CGFloat) -> CGFloat {
        max(width * 4, 8000)
    }

    static func isFrameOnScreen(_ frame: CGRect, screen: CGRect) -> Bool {
        !frame.isEmpty && frame.origin.x.isFinite && frame.origin.y.isFinite
            && screen.contains(CGPoint(x: frame.midX, y: frame.midY))
    }

    static func isInTray(itemMidX: CGFloat, leftBoundaryX: CGFloat, rightBoundaryX: CGFloat) -> Bool {
        itemMidX >= leftBoundaryX && itemMidX < rightBoundaryX
    }

    static func sourceRect(for item: CGRect, in display: CGRect) -> CGRect {
        item.offsetBy(dx: -display.minX, dy: -display.minY)
    }
}
