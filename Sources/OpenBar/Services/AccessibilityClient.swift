import ApplicationServices

@MainActor
enum AccessibilityClient {
    static func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    static func elementAttribute(_ name: String, of element: AXUIElement) -> AXUIElement? {
        guard let value = attribute(name, of: element), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    static func children(of element: AXUIElement) -> [AXUIElement] {
        guard let value = attribute(kAXChildrenAttribute, of: element),
              CFGetTypeID(value) == CFArrayGetTypeID() else { return [] }
        let array = unsafeDowncast(value, to: CFArray.self)
        return (0..<CFArrayGetCount(array)).compactMap { index in
            guard let pointer = CFArrayGetValueAtIndex(array, index) else { return nil }
            let child = Unmanaged<CFTypeRef>.fromOpaque(pointer).takeUnretainedValue()
            guard CFGetTypeID(child) == AXUIElementGetTypeID() else { return nil }
            return unsafeDowncast(child, to: AXUIElement.self)
        }
    }

    static func stringAttribute(_ name: String, of element: AXUIElement) -> String? {
        guard let value = attribute(name, of: element), CFGetTypeID(value) == CFStringGetTypeID() else { return nil }
        let text = (value as! String).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    static func frame(of element: AXUIElement) -> CGRect? {
        guard let position = attribute(kAXPositionAttribute, of: element),
              let size = attribute(kAXSizeAttribute, of: element),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        let positionValue = unsafeDowncast(position, to: AXValue.self)
        let sizeValue = unsafeDowncast(size, to: AXValue.self)
        guard AXValueGetType(positionValue) == .cgPoint, AXValueGetType(sizeValue) == .cgSize else { return nil }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &point), AXValueGetValue(sizeValue, .cgSize, &dimensions),
              point.x.isFinite, point.y.isFinite, dimensions.width.isFinite, dimensions.height.isFinite,
              dimensions.width > 0, dimensions.height > 0 else { return nil }
        return CGRect(origin: point, size: dimensions)
    }
}
