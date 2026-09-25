import Carbon.HIToolbox

/// Globales Tastenkürzel über die Carbon-API (braucht keine Bedienungshilfen-Freigabe).
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void

    init(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue().action()
            return noErr
        }, 1, &spec, context, &handlerRef)
        let id = EventHotKeyID(signature: OSType(0x4249_4C59), id: 1) // 'BILY'
        RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }

    /// ⌃⌥B – „B“ wie Billy.
    static func billyDefault(action: @escaping () -> Void) -> HotKey {
        HotKey(keyCode: UInt32(kVK_ANSI_B), modifiers: UInt32(controlKey | optionKey), action: action)
    }
}
