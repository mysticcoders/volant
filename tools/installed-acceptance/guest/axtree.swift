import AppKit
import ApplicationServices

/// Reads an app's accessibility tree through AXUIElement directly, as VoiceOver does, instead of
/// System Events, whose name-based element references resolve every element sharing a name to
/// the first one. Runs from the guest's SSH session, which holds the image's Accessibility grant.
///
/// Usage: axtree <bundle id> dump <window title>
///        axtree <bundle id> press <window title> <role> <index>   (index among that role, from 1)
///        axtree <bundle id> focused <window title>               (the app's focused element)
let arguments = CommandLine.arguments
guard arguments.count >= 4, let app = NSRunningApplication.runningApplications(withBundleIdentifier: arguments[1]).first else {
    print("usage: axtree <bundle id> dump|press <window title> [role index]")
    exit(2)
}

func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value as? T
}

func frame(_ element: AXUIElement) -> String {
    var point = CGPoint.zero, size = CGSize.zero
    if let value: AXValue = attribute(element, kAXPositionAttribute) { AXValueGetValue(value, .cgPoint, &point) }
    if let value: AXValue = attribute(element, kAXSizeAttribute) { AXValueGetValue(value, .cgSize, &size) }
    return "\(Int(point.x)) \(Int(point.y)) \(Int(size.width)) \(Int(size.height))"
}

func walk(_ element: AXUIElement, _ visit: (AXUIElement) -> Void) {
    visit(element)
    for child in (attribute(element, kAXChildrenAttribute) as [AXUIElement]?) ?? [] { walk(child, visit) }
}

let root = AXUIElementCreateApplication(app.processIdentifier)
let windows: [AXUIElement] = attribute(root, kAXWindowsAttribute) ?? []
guard let window = windows.first(where: { (attribute($0, kAXTitleAttribute) as String?) == arguments[3] }) else {
    print("no window titled \(arguments[3])")
    exit(1)
}
switch arguments[2] {
case "dump":
    walk(window) { element in
        let role: String = attribute(element, kAXRoleAttribute) ?? ""
        let title: String = attribute(element, kAXTitleAttribute) ?? ""
        let description: String = attribute(element, kAXDescriptionAttribute) ?? ""
        let label: String = attribute(element, "AXLabel") ?? ""
        print([role, title, description, label, frame(element)].joined(separator: " | "))
    }
case "focused":
    guard let element: AXUIElement = attribute(root, kAXFocusedUIElementAttribute) else { print("none"); exit(0) }
    let role: String = attribute(element, kAXRoleAttribute) ?? ""
    let title: String = attribute(element, kAXTitleAttribute) ?? ""
    let description: String = attribute(element, kAXDescriptionAttribute) ?? ""
    print([role, title, description, frame(element)].joined(separator: " | "))
case "press":
    guard arguments.count >= 6, let index = Int(arguments[5]) else { exit(2) }
    var matches: [AXUIElement] = []
    walk(window) { if (attribute($0, kAXRoleAttribute) as String?) == arguments[4] { matches.append($0) } }
    guard index >= 1, index <= matches.count else { print("only \(matches.count) \(arguments[4])"); exit(1) }
    let status = AXUIElementPerformAction(matches[index - 1], kAXPressAction as CFString)
    print("press \(arguments[4]) #\(index): \(status.rawValue)")
default:
    exit(2)
}
