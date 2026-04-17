import Carbon.HIToolbox

/// Registers a system-wide keyboard shortcut using the Carbon Hot Key API.
/// Uses Option+L by default. Does not require Accessibility permission
/// (unlike NSEvent.addGlobalMonitorForEvents).
@MainActor
final class HotkeyManager: Sendable {

    /// Called when the registered hotkey is pressed.
    var onHotkeyPressed: (@MainActor @Sendable () -> Void)?

    private static let hotkeyID: UInt32 = 1
    /// Four-char signature "AOPR" (Agent Operator)
    private static let signature: OSType = OSType(0x414F5052)

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    init() {
        registerHotkey(keyCode: 0x25, modifiers: UInt32(optionKey))
    }

    deinit {
        MainActor.assumeIsolated {
            unregisterHotkey()
            removeEventHandler()
        }
    }

    // MARK: - Public

    /// Re-register the hotkey with a different key combo.
    func updateHotkey(keyCode: UInt32, modifiers: UInt32) {
        unregisterHotkey()
        registerHotkey(keyCode: keyCode, modifiers: modifiers)
    }

    // MARK: - Registration

    private func registerHotkey(keyCode: UInt32, modifiers: UInt32) {
        installEventHandlerIfNeeded()

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.hotkeyID)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode, modifiers, hotKeyID,
            GetApplicationEventTarget(), 0, &ref
        )

        guard status == noErr else {
            NSLog("[HotkeyManager] RegisterEventHotKey failed: %d", status)
            return
        }

        hotKeyRef = ref
        NSLog("[HotkeyManager] Registered hotkey (keyCode=0x%02X, modifiers=0x%04X)",
              keyCode, modifiers)
    }

    private func unregisterHotkey() {
        guard let ref = hotKeyRef else { return }
        UnregisterEventHotKey(ref)
        hotKeyRef = nil
        NSLog("[HotkeyManager] Unregistered hotkey")
    }

    // MARK: - Carbon Event Handler

    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let userData = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let event, let userData else { return noErr }

                var hotKeyID = EventHotKeyID()
                let s = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard s == noErr else { return noErr }

                let mgr = Unmanaged<HotkeyManager>.fromOpaque(userData)
                    .takeUnretainedValue()
                Task { @MainActor in
                    mgr.onHotkeyPressed?()
                }
                return noErr
            },
            1,
            &eventType,
            userData,
            &eventHandlerRef
        )
    }

    private func removeEventHandler() {
        guard let ref = eventHandlerRef else { return }
        RemoveEventHandler(ref)
        eventHandlerRef = nil
    }
}
