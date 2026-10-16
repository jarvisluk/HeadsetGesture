import ApplicationServices
import AppKit

struct FocusedInputLocation {
    let frame: CGRect
    let screen: NSScreen
}

enum FocusedInputLocator {
    private static let supportedRoles: Set<String> = [
        kAXTextFieldRole as String,
        kAXTextAreaRole as String,
        kAXComboBoxRole as String,
        "AXSearchField"
    ]

    private static let messagingTimeout: Float = 0.1

    static func current() -> FocusedInputLocation? {
        guard AXIsProcessTrusted() else { return nil }

        let systemWideElement = AXUIElementCreateSystemWide()
        // This runs on the main thread at the start of every press. Without a short
        // timeout an unresponsive frontmost app would stall input handling for up
        // to the default AX timeout (about 6 seconds).
        AXUIElementSetMessagingTimeout(systemWideElement, messagingTimeout)
        guard let focusedValue = attribute(
            kAXFocusedUIElementAttribute as CFString,
            from: systemWideElement
        ) else {
            return nil
        }
        let focusedElement = focusedValue as! AXUIElement
        AXUIElementSetMessagingTimeout(focusedElement, messagingTimeout)

        guard let role = attribute(kAXRoleAttribute as CFString, from: focusedElement) as? String,
              supportedRoles.contains(role),
              let position = pointAttribute(kAXPositionAttribute as CFString, from: focusedElement),
              let size = sizeAttribute(kAXSizeAttribute as CFString, from: focusedElement),
              size.width > 0,
              size.height > 0 else {
            return nil
        }

        return appKitLocation(for: CGRect(origin: position, size: size))
    }

    private static func attribute(
        _ name: CFString,
        from element: AXUIElement
    ) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name, &value) == .success else {
            return nil
        }
        return value
    }

    private static func pointAttribute(
        _ name: CFString,
        from element: AXUIElement
    ) -> CGPoint? {
        guard let value = attribute(name, from: element),
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        var point = CGPoint.zero
        guard AXValueGetValue(value as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }

    private static func sizeAttribute(
        _ name: CFString,
        from element: AXUIElement
    ) -> CGSize? {
        guard let value = attribute(name, from: element),
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        var size = CGSize.zero
        guard AXValueGetValue(value as! AXValue, .cgSize, &size) else { return nil }
        return size
    }

    private static func appKitLocation(for accessibilityFrame: CGRect) -> FocusedInputLocation? {
        let screens = NSScreen.screens.compactMap { screen -> (NSScreen, CGRect)? in
            guard let number = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber else {
                return nil
            }
            return (screen, CGDisplayBounds(CGDirectDisplayID(number.uint32Value)))
        }

        let target = screens.first { _, quartzFrame in
            quartzFrame.contains(
                CGPoint(x: accessibilityFrame.midX, y: accessibilityFrame.midY)
            )
        } ?? screens.max { lhs, rhs in
            intersectionArea(accessibilityFrame, lhs.1)
                < intersectionArea(accessibilityFrame, rhs.1)
        }
        guard let (screen, quartzFrame) = target else { return nil }

        let appKitFrame = CGRect(
            x: screen.frame.minX + accessibilityFrame.minX - quartzFrame.minX,
            y: screen.frame.maxY - (accessibilityFrame.minY - quartzFrame.minY)
                - accessibilityFrame.height,
            width: accessibilityFrame.width,
            height: accessibilityFrame.height
        )
        return FocusedInputLocation(frame: appKitFrame, screen: screen)
    }

    private static func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        return intersection.width * intersection.height
    }
}
