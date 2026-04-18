import Carbon.HIToolbox

/// Registers system-wide keyboard shortcuts using the Carbon Hot Key API.
/// Supports multiple hotkeys keyed by numeric ID. Does not require Accessibility
/// permission (unlike NSEvent.addGlobalMonitorForEvents).
@MainActor
final class HotkeyManager: Sendable {

    private struct Registration {
        let handler: @MainActor @Sendable () -> Void
        var hotKeyRef: EventHotKeyRef?
    }

    private var registrations: [UInt32: Registration] = [:]
    private var eventHandlerRef: EventHandlerRef?

    /// Register a global hotkey with the given numeric `id`.
    /// If a hotkey with the same `id` already exists it is unregistered first.
    func register(id: UInt32, keyCode: UInt32, modifiers: UInt32,
                  handler: @escaping @MainActor @Sendable () -> Void) {
        // Replace any existing registration with the same id
        unregister(id: id)

        // Lazily install the shared Carbon event handler
        installEventHandlerIfNeeded()

        // Register the hotkey with Carbon
        let hotKeyID = EventHotKeyID(signature: OSType(0x43575643), id: id) // "CWVC"
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode, modifiers, hotKeyID,
            GetApplicationEventTarget(), 0, &hotKeyRef
        )

        guard status == noErr else {
            NSLog("[HotkeyManager] RegisterEventHotKey failed for id %d: %d", id, status)
            return
        }

        registrations[id] = Registration(handler: handler, hotKeyRef: hotKeyRef)
        NSLog("[HotkeyManager] Registered hotkey id=%d (keyCode=0x%02X, modifiers=0x%04X)",
              id, keyCode, modifiers)
    }

    /// Unregister a previously registered hotkey by `id`. No-op if not found.
    func unregister(id: UInt32) {
        guard let reg = registrations.removeValue(forKey: id) else { return }
        if let ref = reg.hotKeyRef {
            UnregisterEventHotKey(ref)
        }
        NSLog("[HotkeyManager] Unregistered hotkey id=%d", id)
        removeEventHandlerIfEmpty()
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
                let id = hotKeyID.id
                Task { @MainActor in
                    mgr.registrations[id]?.handler()
                }
                return noErr
            },
            1,
            &eventType,
            userData,
            &eventHandlerRef
        )
    }

    private func removeEventHandlerIfEmpty() {
        guard registrations.isEmpty, let ref = eventHandlerRef else { return }
        RemoveEventHandler(ref)
        eventHandlerRef = nil
    }
}
