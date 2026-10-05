import AppKit

@MainActor
enum TrayPopoverContent {
    static func make(items: [HiddenItem], target: AnyObject, action: Selector) -> (NSViewController, [ObjectIdentifier: HiddenItem]) {
        let background = NSVisualEffectView()
        background.material = .menu
        background.blendingMode = .behindWindow
        background.state = .active
        let grid = NSStackView()
        grid.orientation = .vertical
        grid.alignment = .leading
        grid.spacing = 6
        grid.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        var mapping: [ObjectIdentifier: HiddenItem] = [:]
        let heading = NSTextField(labelWithString: "Hidden menu bar items")
        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        grid.addArrangedSubview(heading)
        for item in items {
            let button = NSButton(title: item.name, image: item.image, target: target, action: action)
            button.bezelStyle = .recessed
            button.imagePosition = .imageLeading
            button.imageScaling = .scaleProportionallyDown
            button.alignment = .left
            button.font = .systemFont(ofSize: 12)
            button.lineBreakMode = .byTruncatingTail
            button.toolTip = item.imageIsFallback ? "\(item.name) · App icon preview" : item.name
            button.setAccessibilityLabel("Open \(item.name)")
            button.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([button.widthAnchor.constraint(equalToConstant: 280), button.heightAnchor.constraint(equalToConstant: 34)])
            mapping[ObjectIdentifier(button)] = item
            grid.addArrangedSubview(button)
        }
        let native = ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27
        let hint = NSTextField(wrappingLabelWithString: native ? "Change app visibility in Manage Menu Bar. All icons from an app move together." : "Command-drag icons in the menu bar to move them between tiers.")
        hint.font = .systemFont(ofSize: 10)
        hint.textColor = .secondaryLabelColor
        hint.alignment = .center
        hint.preferredMaxLayoutWidth = 280
        hint.widthAnchor.constraint(equalToConstant: 280).isActive = true
        grid.addArrangedSubview(hint)
        grid.translatesAutoresizingMaskIntoConstraints = false
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = grid
        scroll.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(scroll)
        NSLayoutConstraint.activate([
            grid.widthAnchor.constraint(equalToConstant: 304),
            scroll.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: background.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: background.bottomAnchor)
        ])
        let size = grid.fittingSize
        grid.setFrameSize(size)
        let controller = NSViewController()
        controller.view = background
        controller.preferredContentSize = NSSize(width: 320, height: min(400, size.height))
        background.setFrameSize(controller.preferredContentSize)
        return (controller, mapping)
    }

    static func message(_ text: String) -> NSViewController {
        let controller = NSViewController()
        controller.view = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 96))
        let label = NSTextField(wrappingLabelWithString: text)
        label.frame = NSRect(x: 12, y: 12, width: 296, height: 72)
        controller.view.addSubview(label)
        controller.preferredContentSize = controller.view.frame.size
        return controller
    }
}
