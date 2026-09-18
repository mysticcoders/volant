import Carbon.HIToolbox
import OSLog

/// Global hotkeys through Carbon's RegisterEventHotKey. Needs no Accessibility or Input Monitoring grant.
final class HotKeyCenter {
    static let shared = HotKeyCenter()
    private static let signature: OSType = 0x5645_595F
    private static let logger = Logger(subsystem: "com.mysticcoders.volant", category: "HotKeys")

    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?

    private init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr, hotKeyID.signature == HotKeyCenter.signature else { return OSStatus(eventNotHandledErr) }
            HotKeyCenter.shared.fire(hotKeyID.id)
            return noErr
        }, 1, &spec, nil, &eventHandler)
        if status != noErr { Self.logger.error("Hotkey event handler installation failed: \(status)") }
    }

    @discardableResult
    func register(_ combo: KeyCombo, handler: @escaping () -> Void) -> UInt32? {
        guard eventHandler != nil else { return nil }
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: HotKeyCenter.signature, id: id)
        let status = RegisterEventHotKey(combo.keyCode, combo.carbonModifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            Self.logger.error("Hotkey registration failed: \(status)")
            return nil
        }
        handlers[id] = handler
        refs[id] = ref
        return id
    }

    func isAvailable(_ combo: KeyCombo) -> Bool {
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(combo.keyCode, combo.carbonModifiers,
                                        EventHotKeyID(signature: Self.signature, id: 0), GetApplicationEventTarget(), 0, &ref)
        if let ref { UnregisterEventHotKey(ref) }
        return status == noErr
    }

    func unregisterAll() {
        for ref in refs.values { UnregisterEventHotKey(ref) }
        refs.removeAll()
        handlers.removeAll()
    }

    private func fire(_ id: UInt32) {
        handlers[id]?()
    }
}
