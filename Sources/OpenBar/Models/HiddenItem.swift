import AppKit
import ApplicationServices

@MainActor
struct HiddenItem {
    let identifier: String
    let name: String
    let image: NSImage
    let element: AXUIElement
    let bundleIdentifier: String?
    let processIdentifier: pid_t
    let frame: CGRect
    let displayID: CGDirectDisplayID?
    /// True when the icon represents the owning app rather than a screenshot.
    let imageIsFallback: Bool

    init(name: String, image: NSImage, element: AXUIElement, identifier: String? = nil,
         bundleIdentifier: String? = nil, processIdentifier: pid_t = 0,
         frame: CGRect = .zero, displayID: CGDirectDisplayID? = nil, imageIsFallback: Bool = false) {
        self.identifier = identifier ?? name
        self.name = name
        self.image = image
        self.element = element
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = processIdentifier
        self.frame = frame
        self.displayID = displayID
        self.imageIsFallback = imageIsFallback
    }
}
