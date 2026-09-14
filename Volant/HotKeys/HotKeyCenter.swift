import Carbon.HIToolbox

/// Global hotkeys through Carbon's RegisterEventHotKey. Needs no Accessibility or Input Monitoring grant.
final class HotKeyCenter {
    static let shared = HotKeyCenter()
    private static let signature: OSType = 0x5645_595F

    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?

    private init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            if status == noErr { HotKeyCenter.shared.fire(hotKeyID.id) }
            return noErr
        }, 1, &spec, nil, &eventHandler)
    }

    @discardableResult
    func register(_ combo: KeyCombo, handler: @escaping () -> Void) -> UInt32? {
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: HotKeyCenter.signature, id: id)
        let status = RegisterEventHotKey(combo.keyCode, combo.carbonModifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return nil }
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
