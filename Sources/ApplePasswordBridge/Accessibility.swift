import AppKit
import ApplicationServices

struct AccessibilityNode {
    let element: AXUIElement
    let role: String
    let text: String
    let value: String?
    let position: CGPoint?

    var isTextInput: Bool {
        role == (kAXTextFieldRole as String)
            || role == (kAXTextAreaRole as String)
            || role == "AXSecureTextField"
    }
}

enum AccessibilityTree {
    private static let textAttributes: [CFString] = [
        kAXTitleAttribute as CFString,
        kAXValueAttribute as CFString,
        kAXDescriptionAttribute as CFString,
        kAXHelpAttribute as CFString,
        "AXURL" as CFString,
        kAXIdentifierAttribute as CFString
    ]

    static func application(bundleIdentifier: String) -> (NSRunningApplication, AXUIElement)? {
        guard let app = NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier
        ).first else {
            return nil
        }
        return (app, AXUIElementCreateApplication(app.processIdentifier))
    }

    static func windows(of application: AXUIElement) -> [AXUIElement] {
        copy(application, attribute: kAXWindowsAttribute as CFString) as? [AXUIElement] ?? []
    }

    static func enableEnhancedUserInterface(_ application: AXUIElement) {
        _ = AXUIElementSetAttributeValue(
            application,
            "AXEnhancedUserInterface" as CFString,
            kCFBooleanTrue
        )
    }

    static func collect(from root: AXUIElement, maxDepth: Int = 12, maxNodes: Int = 800) -> [AccessibilityNode] {
        var result: [AccessibilityNode] = []
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var index = 0

        while index < queue.count && result.count < maxNodes {
            let (element, depth) = queue[index]
            index += 1

            let role = (copy(element, attribute: kAXRoleAttribute as CFString) as? String) ?? ""
            let value = copy(element, attribute: kAXValueAttribute as CFString) as? String
            let values = textAttributes.compactMap { copy(element, attribute: $0) as? String }
            result.append(AccessibilityNode(
                element: element,
                role: role,
                text: values.joined(separator: "\n"),
                value: value,
                position: point(element, attribute: kAXPositionAttribute as CFString)
            ))

            guard depth < maxDepth else { continue }
            let children = copy(
                element,
                attribute: kAXChildrenAttribute as CFString
            ) as? [AXUIElement] ?? []
            queue.append(contentsOf: children.map { ($0, depth + 1) })
        }
        return result
    }

    static func title(of element: AXUIElement) -> String? {
        copy(element, attribute: kAXTitleAttribute as CFString) as? String
    }

    static func focus(_ element: AXUIElement) -> Bool {
        AXUIElementSetAttributeValue(
            element,
            kAXFocusedAttribute as CFString,
            kCFBooleanTrue
        ) == .success
    }

    static func raise(_ window: AXUIElement) {
        _ = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        _ = AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        _ = AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    }

    private static func copy(_ element: AXUIElement, attribute: CFString) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value
    }

    private static func point(_ element: AXUIElement, attribute: CFString) -> CGPoint? {
        guard let raw = copy(element, attribute: attribute), CFGetTypeID(raw) == AXValueGetTypeID() else {
            return nil
        }
        var point = CGPoint.zero
        guard AXValueGetValue(raw as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }
}
