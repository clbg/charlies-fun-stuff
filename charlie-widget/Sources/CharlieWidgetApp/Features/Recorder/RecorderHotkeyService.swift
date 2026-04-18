import Foundation

/// Manages three global hotkeys for toggling Recorder (one per AudioSource).
@MainActor
@Observable
final class RecorderHotkeyService: Sendable {

    // MARK: - Config

    struct HotkeyConfig: Sendable {
        var keyCode: UInt32
        var modifiers: UInt32
    }

    private(set) var enabled: Bool = false
    private(set) var configs: [AudioSource: HotkeyConfig] = RecorderHotkeyService.defaultConfigs

    // MARK: - Dependencies

    private var hotkeyManager: HotkeyManager?
    private weak var recorderStore: RecorderStore?
    private weak var messageStore: MessageStore?

    // MARK: - Constants

    private static let defaultConfigs: [AudioSource: HotkeyConfig] = [
        .mic:    HotkeyConfig(keyCode: 0x12, modifiers: 0x0800), // ⌥1
        .system: HotkeyConfig(keyCode: 0x13, modifiers: 0x0800), // ⌥2
        .both:   HotkeyConfig(keyCode: 0x14, modifiers: 0x0800), // ⌥3
    ]

    private static func hotkeyID(for source: AudioSource) -> UInt32 {
        switch source {
        case .mic:    return 10
        case .system: return 11
        case .both:   return 12
        }
    }

    private static let enabledKey = "CharlieWidget.recorder.hotkeys.enabled"

    private static func keyCodeKey(for source: AudioSource) -> String {
        "CharlieWidget.recorder.hotkey.\(source.rawValue).keyCode"
    }
    private static func modifiersKey(for source: AudioSource) -> String {
        "CharlieWidget.recorder.hotkey.\(source.rawValue).modifiers"
    }

    // MARK: - Setup

    func setup(recorderStore: RecorderStore, messageStore: MessageStore, hotkeyManager: HotkeyManager) {
        self.recorderStore = recorderStore
        self.messageStore = messageStore
        self.hotkeyManager = hotkeyManager
        loadConfig()
        if enabled {
            registerAll()
        }
    }

    // MARK: - Public API

    func setEnabled(_ newEnabled: Bool) {
        enabled = newEnabled
        UserDefaults.standard.set(newEnabled, forKey: Self.enabledKey)
        if newEnabled {
            registerAll()
        } else {
            unregisterAll()
        }
    }

    func updateHotkey(for source: AudioSource, keyCode: UInt32, modifiers: UInt32) {
        configs[source] = HotkeyConfig(keyCode: keyCode, modifiers: modifiers)
        saveConfig(for: source)
        if enabled {
            registerHotkey(for: source)
        }
    }

    func displayName(for source: AudioSource) -> String {
        guard let config = configs[source] else { return "?" }
        var s = ""
        if config.modifiers & 0x1000 != 0 { s += "\u{2303}" } // ⌃
        if config.modifiers & 0x0800 != 0 { s += "\u{2325}" } // ⌥
        if config.modifiers & 0x0200 != 0 { s += "\u{21E7}" } // ⇧
        if config.modifiers & 0x0100 != 0 { s += "\u{2318}" } // ⌘
        s += VoiceCommandService.keyName(config.keyCode)
        return s
    }

    func keyCode(for source: AudioSource) -> UInt32 {
        configs[source]?.keyCode ?? 0
    }

    func modifiers(for source: AudioSource) -> UInt32 {
        configs[source]?.modifiers ?? 0
    }

    // MARK: - Hotkey Handler

    private func handleHotkey(source: AudioSource) {
        guard let store = recorderStore else { return }

        switch store.state {
        case .recording:
            Task { await store.stopRecording() }
            toast("Recording stopped", level: .info)
        case .idle:
            Task { await store.startRecording(source: source) }
            toast("Recording \(source.rawValue)\u{2026} press hotkey to stop", level: .info)
        case .stopping:
            break // debounce
        }
    }

    // MARK: - Registration

    private func registerAll() {
        for source in [AudioSource.mic, .system, .both] {
            registerHotkey(for: source)
        }
    }

    private func registerHotkey(for source: AudioSource) {
        guard let mgr = hotkeyManager, let config = configs[source] else { return }
        mgr.register(
            id: Self.hotkeyID(for: source),
            keyCode: config.keyCode,
            modifiers: config.modifiers,
            handler: { [weak self] in self?.handleHotkey(source: source) }
        )
    }

    private func unregisterAll() {
        for source in [AudioSource.mic, .system, .both] {
            hotkeyManager?.unregister(id: Self.hotkeyID(for: source))
        }
    }

    // MARK: - Toast

    private func toast(_ body: String, level: ToastLevel) {
        guard let store = messageStore else { return }
        store.addMessage(title: "Recorder", subtitle: nil, body: body, level: level)
        if !store.muted {
            ToastWindow.show(title: "Recorder", subtitle: nil, body: body, level: level)
        }
    }

    // MARK: - Config Persistence

    private func loadConfig() {
        let ud = UserDefaults.standard
        if ud.object(forKey: Self.enabledKey) != nil {
            enabled = ud.bool(forKey: Self.enabledKey)
        }
        for source in [AudioSource.mic, .system, .both] {
            let kcKey = Self.keyCodeKey(for: source)
            let modKey = Self.modifiersKey(for: source)
            if ud.object(forKey: kcKey) != nil, ud.object(forKey: modKey) != nil {
                configs[source] = HotkeyConfig(
                    keyCode: UInt32(ud.integer(forKey: kcKey)),
                    modifiers: UInt32(ud.integer(forKey: modKey))
                )
            }
        }
    }

    private func saveConfig(for source: AudioSource) {
        guard let config = configs[source] else { return }
        let ud = UserDefaults.standard
        ud.set(Int(config.keyCode), forKey: Self.keyCodeKey(for: source))
        ud.set(Int(config.modifiers), forKey: Self.modifiersKey(for: source))
    }
}
