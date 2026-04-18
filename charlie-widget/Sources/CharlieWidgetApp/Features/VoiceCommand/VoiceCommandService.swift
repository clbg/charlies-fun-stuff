@preconcurrency import AVFAudio
import AppKit

/// Global hotkey -> record mic -> transcribe -> send to iTerm's Claude Code.
@MainActor
@Observable
final class VoiceCommandService: Sendable {

    // MARK: - State

    enum State: String, Sendable {
        case idle
        case recording
        case transcribing
    }

    /// How to pick which CC session receives the transcribed text.
    enum SessionTarget: String, CaseIterable, Sendable {
        case focusedFirst = "Focused first"
        case searchAll = "Search all"
    }

    private(set) var state: State = .idle

    // MARK: - Dependencies

    private var hotkeyManager: HotkeyManager?
    private let transcriptionEngine = TranscriptionEngine()
    private let micRecorder = VoiceMicRecorder()
    private var messageStore: MessageStore?

    // Hotkey config (defaults: Option+V)
    private(set) var keyCode: UInt32 = 0x09
    private(set) var modifiers: UInt32 = 0x0800
    private(set) var hotkeyEnabled: Bool = true
    private(set) var sessionTarget: SessionTarget = .focusedFirst

    private static let keyCodeKey = "CharlieWidget.voiceCommand.keyCode"
    private static let modifiersKey = "CharlieWidget.voiceCommand.modifiers"
    private static let enabledKey = "CharlieWidget.voiceCommand.enabled"
    private static let sessionTargetKey = "CharlieWidget.voiceCommand.sessionTarget"

    // MARK: - Setup

    func setup(messageStore: MessageStore, hotkeyManager: HotkeyManager) {
        self.messageStore = messageStore
        self.hotkeyManager = hotkeyManager
        loadConfig()
        if hotkeyEnabled {
            registerCurrentHotkey()
        }
    }

    // MARK: - Hotkey Configuration

    func updateHotkey(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        saveConfig()
        registerCurrentHotkey()
    }

    func setSessionTarget(_ target: SessionTarget) {
        sessionTarget = target
        UserDefaults.standard.set(target.rawValue, forKey: Self.sessionTargetKey)
    }

    func setEnabled(_ enabled: Bool) {
        hotkeyEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        if enabled {
            registerCurrentHotkey()
        } else {
            hotkeyManager?.unregister(id: 1)
        }
    }

    var hotkeyDisplayName: String {
        var s = ""
        if modifiers & 0x1000 != 0 { s += "\u{2303}" } // ⌃
        if modifiers & 0x0800 != 0 { s += "\u{2325}" } // ⌥
        if modifiers & 0x0200 != 0 { s += "\u{21E7}" } // ⇧
        if modifiers & 0x0100 != 0 { s += "\u{2318}" } // ⌘
        s += Self.keyName(keyCode)
        return s
    }

    static func keyName(_ keyCode: UInt32) -> String {
        let map: [UInt32: String] = [
            0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H",
            0x05: "G", 0x06: "Z", 0x07: "X", 0x08: "C", 0x09: "V",
            0x0B: "B", 0x0C: "Q", 0x0D: "W", 0x0E: "E", 0x0F: "R",
            0x10: "Y", 0x11: "T", 0x12: "1", 0x13: "2", 0x14: "3",
            0x15: "4", 0x16: "6", 0x17: "5", 0x18: "=", 0x19: "9",
            0x1A: "7", 0x1B: "-", 0x1C: "8", 0x1D: "0", 0x1E: "]",
            0x1F: "O", 0x20: "U", 0x21: "[", 0x22: "I", 0x23: "P",
            0x24: "Return", 0x25: "L", 0x26: "J", 0x28: "K",
            0x2B: ",", 0x2C: "/", 0x2D: "N", 0x2E: "M", 0x2F: ".",
            0x31: "Space",
            0x60: "F5", 0x61: "F6", 0x62: "F7", 0x63: "F3",
            0x64: "F8", 0x65: "F9", 0x67: "F11", 0x6D: "F10",
            0x6F: "F12", 0x76: "F4", 0x78: "F2", 0x7A: "F1",
            0x7B: "\u{2190}", 0x7C: "\u{2192}", 0x7D: "\u{2193}", 0x7E: "\u{2191}",
        ]
        return map[keyCode] ?? "Key\(keyCode)"
    }

    // MARK: - Public API (for IPC/CLI triggering)

    func triggerStart() {
        guard state == .idle else { return }
        startRecording()
    }

    func triggerStop() async {
        guard state == .recording else { return }
        await stopAndTranscribe()
    }

    // MARK: - Hotkey Handler

    private func handleHotkey() {
        switch state {
        case .idle:
            startRecording()
        case .recording:
            Task { await stopAndTranscribe() }
        case .transcribing:
            break
        }
    }

    // MARK: - Recording

    private func startRecording() {
        do {
            _ = try micRecorder.start()
            state = .recording
            toast("Recording\u{2026} press \(hotkeyDisplayName) to stop", level: .info)
            NSLog("[VoiceCommand] recording started")
        } catch {
            toast("Mic error: \(error.localizedDescription)", level: .error)
        }
    }

    private func stopAndTranscribe() async {
        micRecorder.stop()
        state = .transcribing
        toast("Transcribing\u{2026}", level: .info)
        NSLog("[VoiceCommand] recording stopped, transcribing")

        guard let fileURL = micRecorder.fileURL else {
            state = .idle
            toast("No recording found", level: .error)
            return
        }

        do {
            let segments = try await transcriptionEngine.transcribe(audioURL: fileURL)
            let text = segments.map(\.text).joined(separator: " ")
            micRecorder.cleanup()

            guard !text.isEmpty else {
                toast("No speech detected", level: .warning)
                state = .idle
                return
            }

            NSLog("[VoiceCommand] transcribed: %@", text)
            sendToiTerm(text: text)
            toast(text, level: .success)
            state = .idle
        } catch {
            micRecorder.cleanup()
            toast("Transcription failed: \(error.localizedDescription)", level: .error)
            state = .idle
        }
    }

    // MARK: - iTerm Integration

    private func sendToiTerm(text: String) {
        let escaped = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        // Build AppleScript based on session target strategy
        let focusedFirstBlock = """
            -- Focused first: check current session before searching
            set csName to name of current session of current window
            if csName ends with "(node)" or csName contains "claude" then
                tell current session of current window to write text "\(escaped)"
                return "sent"
            end if
        """
        let searchBlock = """
            -- Search all sessions for a CC session
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        set sName to name of s
                        if sName ends with "(node)" or sName contains "claude" then
                            tell s
                                select
                                write text "\(escaped)"
                            end tell
                            return "sent"
                        end if
                    end repeat
                end repeat
            end repeat
        """

        var script = "tell application \"iTerm\"\n    activate\n"
        switch sessionTarget {
        case .focusedFirst:
            script += focusedFirstBlock + "\n" + searchBlock
        case .searchAll:
            script += searchBlock
        }
        script += "\n    return \"not_found\"\nend tell"

        var error: NSDictionary?
        let result = NSAppleScript(source: script)?.executeAndReturnError(&error)

        if let error {
            NSLog("[VoiceCommand] AppleScript error: %@", error)
            toast("Failed to send to iTerm", level: .error)
            return
        }

        if result?.stringValue == "sent" {
            NSLog("[VoiceCommand] sent to Claude Code session (strategy: %@)", sessionTarget.rawValue)
            return
        }

        // No CC session found — start one, wait, then send prompt
        NSLog("[VoiceCommand] no Claude Code session found, starting one")
        let startClaude = """
        tell application "iTerm"
            activate
            if (count of windows) = 0 then
                create window with default profile
            end if
            tell current session of current window
                write text "claude"
            end tell
        end tell
        """
        NSAppleScript(source: startClaude)?.executeAndReturnError(&error)

        Task {
            try? await Task.sleep(for: .seconds(3))
            let sendPrompt = """
            tell application "iTerm"
                tell current session of current window
                    write text "\(escaped)"
                end tell
            end tell
            """
            var sendError: NSDictionary?
            NSAppleScript(source: sendPrompt)?.executeAndReturnError(&sendError)
            if let sendError {
                NSLog("[VoiceCommand] failed to send prompt after starting claude: %@", sendError)
            }
        }
    }

    // MARK: - Toast

    private func toast(_ body: String, level: ToastLevel) {
        guard let store = messageStore else { return }
        store.addMessage(title: "Voice Command", subtitle: nil, body: body, level: level)
        if !store.muted {
            ToastWindow.show(title: "Voice Command", subtitle: nil, body: body, level: level)
        }
    }

    // MARK: - Hotkey Registration

    private func registerCurrentHotkey() {
        hotkeyManager?.register(
            id: 1,
            keyCode: keyCode,
            modifiers: modifiers,
            handler: { [weak self] in self?.handleHotkey() }
        )
    }

    // MARK: - Config Persistence

    private func loadConfig() {
        let ud = UserDefaults.standard
        if ud.object(forKey: Self.keyCodeKey) != nil {
            keyCode = UInt32(ud.integer(forKey: Self.keyCodeKey))
        }
        if ud.object(forKey: Self.modifiersKey) != nil {
            modifiers = UInt32(ud.integer(forKey: Self.modifiersKey))
        }
        if ud.object(forKey: Self.enabledKey) != nil {
            hotkeyEnabled = ud.bool(forKey: Self.enabledKey)
        }
        if let raw = ud.string(forKey: Self.sessionTargetKey),
           let target = SessionTarget(rawValue: raw) {
            sessionTarget = target
        }
    }

    private func saveConfig() {
        let ud = UserDefaults.standard
        ud.set(Int(keyCode), forKey: Self.keyCodeKey)
        ud.set(Int(modifiers), forKey: Self.modifiersKey)
    }
}

// MARK: - Lightweight mic recorder (16kHz mono WAV for WhisperKit)

final class VoiceMicRecorder: @unchecked Sendable {

    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var converter: AVAudioConverter?
    private let writeQueue = DispatchQueue(label: "com.charlie.widget.voice-mic")
    private(set) var fileURL: URL?

    private static let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16000,
        channels: 1,
        interleaved: false
    )!

    func start() throws -> URL {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let hwFormat = inputNode.outputFormat(forBus: 0)

        guard hwFormat.sampleRate > 0 else {
            throw RecorderError.permissionDenied("Microphone")
        }

        let format = Self.targetFormat
        let conv = AVAudioConverter(from: hwFormat, to: format)!

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-cmd-\(UUID().uuidString).wav")
        let file = try AVAudioFile(forWriting: url, settings: format.settings)

        converter = conv
        audioFile = file
        fileURL = url

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { [weak self] buffer, _ in
            self?.handleBuffer(buffer)
        }

        try engine.start()
        audioEngine = engine
        return url
    }

    func stop() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        writeQueue.sync { audioFile = nil }
        converter = nil
    }

    func cleanup() {
        if let url = fileURL {
            try? FileManager.default.removeItem(at: url)
            fileURL = nil
        }
    }

    private func handleBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let conv = converter else { return }
        let format = Self.targetFormat

        let frameCapacity = AVAudioFrameCount(
            Double(buffer.frameLength) * (format.sampleRate / buffer.format.sampleRate)
        )
        guard frameCapacity > 0,
              let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity)
        else { return }

        var consumed = false
        var error: NSError?
        conv.convert(to: converted, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard error == nil, converted.frameLength > 0 else { return }

        writeQueue.async { [weak self] in
            try? self?.audioFile?.write(from: converted)
        }
    }
}
