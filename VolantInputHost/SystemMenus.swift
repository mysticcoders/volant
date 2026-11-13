import AppKit
import ApplicationServices
import VolantCore

/// A menu bar title or menu item through Accessibility. It reads only the title, the enabled state,
/// the command character and modifiers, and the children list that holds the submenu, and its only
/// action is a press. It never reads values, descriptions, windows or any other attribute.
final class AccessibilityMenuNode: MenuNode {
    static let attributes = [kAXTitleAttribute, kAXEnabledAttribute, kAXMenuItemCmdCharAttribute, kAXMenuItemCmdModifiersAttribute] as CFArray
    private let element: AXUIElement
    let title: String?
    let enabled: Bool
    let commandCharacter: String?
    let commandModifiers: Int?

    /// Reads the four attributes in one round trip; a missing one reads as absent.
    init(_ element: AXUIElement) {
        self.element = element
        AXUIElementSetMessagingTimeout(element, SystemInput.messagingTimeout)
        var values: CFArray?
        let read = AXUIElementCopyMultipleAttributeValues(element, Self.attributes, AXCopyMultipleAttributeOptions(), &values)
        let list = read == .success ? (values as? [Any]) ?? [] : []
        func value(_ index: Int) -> Any? {
            guard index < list.count else { return nil }
            let item = list[index] as CFTypeRef
            return CFGetTypeID(item) == AXValueGetTypeID() ? nil : item
        }
        title = value(0) as? String
        enabled = (value(1) as? Bool) ?? false
        commandCharacter = value(2) as? String
        commandModifiers = value(3) as? Int
    }

    /// The items of the menu this element opens: its children are at most one menu, whose
    /// children are the items.
    func children() -> [MenuNode] {
        guard let menu = Self.elements(element).first else { return [] }
        return Self.elements(menu).map(AccessibilityMenuNode.init)
    }

    func press() -> Bool {
        AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }

    /// The structural children of an element, or none.
    static func elements(_ element: AXUIElement) -> [AXUIElement] {
        AXUIElementSetMessagingTimeout(element, SystemInput.messagingTimeout)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let array = value as? [AXUIElement] else { return [] }
        return array
    }
}

/// The real system calls behind `MenuItemsController`: trust, the process's bundle identifier and
/// activation policy, the app in front (confirmed by its own `AXFrontmost`, as typing does), and
/// the app's menu bar.
final class SystemMenus: MenuSystem {
    func isTrusted() -> Bool {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary)
    }

    func bundleIdentifier(of pid: Int32) -> String? {
        NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }

    func isRegularApp(_ pid: Int32) -> Bool {
        NSRunningApplication(processIdentifier: pid)?.activationPolicy == .regular
    }

    func frontmostPID() -> Int32? {
        SystemInput().frontmostTarget()?.pid
    }

    func menuBar(of pid: Int32) -> [MenuNode]? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, SystemInput.messagingTimeout)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return AccessibilityMenuNode.elements(value as! AXUIElement).map(AccessibilityMenuNode.init)
    }
}
