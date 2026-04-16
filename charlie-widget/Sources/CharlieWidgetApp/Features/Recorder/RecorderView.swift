import SwiftUI

struct RecorderView: View {
    var recorderStore: RecorderStore
    @State private var selectedSource: AudioSource = .both

    var body: some View {
        VStack(spacing: 0) {
            recordingControl
            Divider()
            if recorderStore.todayRecordings.isEmpty && recorderStore.state == .idle {
                emptyPlaceholder
            } else {
                recordingsList
            }
        }
    }

    // MARK: - Recording Control

    private var recordingControl: some View {
        VStack(spacing: 0) {
        HStack(spacing: 12) {
            Button {
                Task {
                    if recorderStore.state == .recording {
                        await recorderStore.stopRecording()
                    } else {
                        await recorderStore.startRecording(source: selectedSource)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(recorderStore.state == .recording ? Color.red : Color.red.opacity(0.6))
                        .frame(width: 10, height: 10)
                    Text(recorderStore.state == .recording ? "Stop" : "Record")
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .buttonStyle(.plain)
            .disabled(recorderStore.state == .stopping)

            // Source picker
            if recorderStore.state == .idle {
                Picker("", selection: $selectedSource) {
                    Image(systemName: "mic.fill").tag(AudioSource.mic)
                    Image(systemName: "speaker.wave.2.fill").tag(AudioSource.system)
                    Image(systemName: "mic.and.signal.meter.fill").tag(AudioSource.both)
                }
                .pickerStyle(.segmented)
                .frame(width: 100)
            }

            if recorderStore.state == .recording {
                Text(formatDuration(recorderStore.elapsedSeconds))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let error = recorderStore.lastError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)

        // Audio level meter + device name
        if recorderStore.state == .recording {
            VStack(spacing: 4) {
                // Level meter bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.gray.opacity(0.2))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(levelColor(recorderStore.audioLevel))
                            .frame(width: geo.size.width * CGFloat(recorderStore.audioLevel))
                            .animation(.linear(duration: 0.1), value: recorderStore.audioLevel)
                    }
                }
                .frame(height: 6)
                .padding(.horizontal, 12)

                // Device name
                if !recorderStore.captureDeviceName.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: recorderStore.currentRecording?.source == .mic
                              ? "mic.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 9))
                        Text(recorderStore.captureDeviceName)
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                }
            }
            .padding(.bottom, 6)
        }
        } // VStack
    }

    // MARK: - Recordings List

    private var recordingsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(recorderStore.todayRecordings) { recording in
                    recordingRow(recording)
                    Divider()
                }
            }
        }
    }

    private func recordingRow(_ recording: Recording) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(formatTime(recording.startedAt))
                    .font(.system(size: 12, weight: .medium))

                HStack(spacing: 4) {
                    if let dur = recording.durationSeconds {
                        Text(formatDuration(dur))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(recording.source.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Empty

    private var emptyPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("No recordings today")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Level Color

    private func levelColor(_ level: Float) -> Color {
        Color.accentColor.opacity(0.4 + Double(level) * 0.6)
    }

    // MARK: - Formatting

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    private func formatTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
