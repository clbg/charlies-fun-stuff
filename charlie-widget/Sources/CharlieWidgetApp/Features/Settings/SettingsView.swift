import SwiftUI
import Carbon.HIToolbox

struct SettingsView: View {

    var voiceCommandService: VoiceCommandService
    var recorderHotkeyService: RecorderHotkeyService
    var recorderStore: RecorderStore

    enum HotkeyTarget: Hashable {
        case voiceCommand
        case recorder(AudioSource)
    }

    @State private var recordingTarget: HotkeyTarget?
    @State private var eventMonitor: Any?

    @AppStorage("CharlieWidget.liveTranscription.enabled") private var liveTranscriptionEnabled: Bool = true
    @AppStorage("CharlieWidget.liveTranscription.micLanguage") private var micLanguage: String = "auto"
    @AppStorage("CharlieWidget.liveTranscription.systemLanguage") private var systemLanguage: String = "auto"

    private static let languageChoices: [(code: String, label: String)] = [
        ("auto", "Auto-detect"),
        ("en", "English"),
        ("zh", "Chinese"),
        ("ja", "Japanese"),
        ("ko", "Korean"),
        ("es", "Spanish"),
        ("fr", "French"),
        ("de", "German"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader("Voice Command")

                toggleRow

                Divider().padding(.horizontal, 12)

                hotkeyRow

                Divider().padding(.horizontal, 12)

                sessionTargetRow

                Divider().padding(.horizontal, 12)

                voiceStatusRow

                Divider().padding(.horizontal, 12)
                    .padding(.bottom, 4)

                sectionHeader("Recorder Hotkeys")

                recorderToggleRow

                Divider().padding(.horizontal, 12)

                ForEach([AudioSource.mic, .system, .both], id: \.self) { source in
                    recorderHotkeyRow(source: source)
                    Divider().padding(.horizontal, 12)
                }

                recorderStatusRow

                Divider().padding(.horizontal, 12)
                    .padding(.bottom, 4)

                sectionHeader("Transcription")

                liveTranscriptionToggleRow

                Divider().padding(.horizontal, 12)

                languageRow(label: "Mic Language", icon: "mic", selection: $micLanguage)

                Divider().padding(.horizontal, 12)

                languageRow(label: "System Language", icon: "speaker.wave.2", selection: $systemLanguage)

                liveTranscriptionFooter
            }
        }
    }

    private func languageRow(label: String, icon: String, selection: Binding<String>) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .font(.system(size: 12))
            Spacer()
            Picker("", selection: selection) {
                ForEach(Self.languageChoices, id: \.code) { choice in
                    Text(choice.label).tag(choice.code)
                }
            }
            .pickerStyle(.menu)
            .controlSize(.small)
            .frame(maxWidth: 140)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Transcription Section

    private var liveTranscriptionToggleRow: some View {
        HStack {
            Label("Real-time Transcription", systemImage: "text.bubble")
                .font(.system(size: 12))
            Spacer()
            Toggle("", isOn: $liveTranscriptionEnabled)
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var liveTranscriptionFooter: some View {
        Text("Transcribe and summarize while recording. Turn off to save CPU and battery.")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Voice Command Section

    private var toggleRow: some View {
        HStack {
            Label("Enabled", systemImage: "mic.circle")
                .font(.system(size: 12))
            Spacer()
            Toggle("", isOn: Binding(
                get: { voiceCommandService.hotkeyEnabled },
                set: { voiceCommandService.setEnabled($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var hotkeyRow: some View {
        HStack {
            Label("Shortcut", systemImage: "keyboard")
                .font(.system(size: 12))
            Spacer()
            hotkeyRecorderButton(
                target: .voiceCommand,
                displayName: voiceCommandService.hotkeyDisplayName
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var sessionTargetRow: some View {
        HStack {
            Label("Multi-CC", systemImage: "rectangle.stack")
                .font(.system(size: 12))
            Spacer()
            Picker("", selection: Binding(
                get: { voiceCommandService.sessionTarget },
                set: { voiceCommandService.setSessionTarget($0) }
            )) {
                ForEach(VoiceCommandService.SessionTarget.allCases, id: \.self) { target in
                    Text(target.rawValue).tag(target)
                }
            }
            .pickerStyle(.menu)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var voiceStatusRow: some View {
        HStack {
            Label("Status", systemImage: "info.circle")
                .font(.system(size: 12))
            Spacer()
            Text(voiceStatusText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var voiceStatusText: String {
        if !voiceCommandService.hotkeyEnabled { return "Disabled" }
        switch voiceCommandService.state {
        case .idle: return "Ready"
        case .recording: return "Recording\u{2026}"
        case .transcribing: return "Transcribing\u{2026}"
        }
    }

    // MARK: - Recorder Section

    private var recorderToggleRow: some View {
        HStack {
            Label("Enabled", systemImage: "record.circle")
                .font(.system(size: 12))
            Spacer()
            Toggle("", isOn: Binding(
                get: { recorderHotkeyService.enabled },
                set: { recorderHotkeyService.setEnabled($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func recorderHotkeyRow(source: AudioSource) -> some View {
        HStack {
            Label(sourceLabel(source), systemImage: sourceIcon(source))
                .font(.system(size: 12))
            Spacer()
            hotkeyRecorderButton(
                target: .recorder(source),
                displayName: recorderHotkeyService.displayName(for: source)
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var recorderStatusRow: some View {
        HStack {
            Label("Status", systemImage: "info.circle")
                .font(.system(size: 12))
            Spacer()
            Text(recorderStatusText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var recorderStatusText: String {
        if !recorderHotkeyService.enabled { return "Disabled" }
        switch recorderStore.state {
        case .idle: return "Ready"
        case .recording:
            let src = recorderStore.currentRecording?.source.rawValue ?? ""
            return "Recording \(src)\u{2026}"
        case .stopping: return "Stopping\u{2026}"
        }
    }

    private func sourceLabel(_ source: AudioSource) -> String {
        switch source {
        case .mic: return "Mic"
        case .system: return "System"
        case .both: return "Both"
        }
    }

    private func sourceIcon(_ source: AudioSource) -> String {
        switch source {
        case .mic: return "mic"
        case .system: return "speaker.wave.2"
        case .both: return "waveform"
        }
    }

    // MARK: - Shared Hotkey Recorder

    @ViewBuilder
    private func hotkeyRecorderButton(target: HotkeyTarget, displayName: String) -> some View {
        let isRecording = recordingTarget == target
        Button {
            if isRecording {
                cancelRecording()
            } else {
                startRecordingHotkey(target)
            }
        } label: {
            Text(isRecording ? "Type shortcut\u{2026}" : displayName)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isRecording ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    private func startRecordingHotkey(_ target: HotkeyTarget) {
        recordingTarget = target
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKeyEvent(event)
            return nil
        }
    }

    private func handleKeyEvent(_ event: NSEvent) {
        if event.keyCode == 53 {
            cancelRecording()
            return
        }

        let mods = carbonModifiers(from: event.modifierFlags)
        guard mods != 0 else { return }

        let kc = UInt32(event.keyCode)

        switch recordingTarget {
        case .voiceCommand:
            voiceCommandService.updateHotkey(keyCode: kc, modifiers: mods)
        case .recorder(let source):
            recorderHotkeyService.updateHotkey(for: source, keyCode: kc, modifiers: mods)
        case nil:
            break
        }

        stopRecording()
    }

    private func cancelRecording() {
        stopRecording()
    }

    private func stopRecording() {
        recordingTarget = nil
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= 0x0100 }
        if flags.contains(.shift) { m |= 0x0200 }
        if flags.contains(.option) { m |= 0x0800 }
        if flags.contains(.control) { m |= 0x1000 }
        return m
    }
}
