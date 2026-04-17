import SwiftUI

struct RecorderView: View {
    var recorderStore: RecorderStore
    @State private var selectedSource: AudioSource = .both
    @State private var expandedTranscriptId: UUID?
    @State private var renamingId: UUID?
    @State private var renameText: String = ""
    @State private var summaryExpanded = false
    @State private var recoveryNoticeDismissed = false

    var body: some View {
        VStack(spacing: 0) {
            if recorderStore.recoveredPartialCount > 0 && !recoveryNoticeDismissed {
                recoveryBanner
            }
            recordingControl
            if recorderStore.state == .recording && recorderStore.isLiveTranscribing {
                Divider()
                liveTranscriptPanel
            }
            if recorderStore.state == .recording, recorderStore.liveSummary != nil {
                Divider()
                liveSummarySection
            }
            Divider()
            if recorderStore.todayRecordings.isEmpty && recorderStore.state == .idle {
                emptyPlaceholder
            } else {
                recordingsList
            }
        }
    }

    // MARK: - Recovery Banner

    private var recoveryBanner: some View {
        let n = recorderStore.recoveredPartialCount
        let label = "Recovered \(n) interrupted transcript\(n == 1 ? "" : "s")"
        return HStack(spacing: 6) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.blue)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
            Spacer()
            Button {
                recoveryNoticeDismissed = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(4)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.blue.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.blue.opacity(0.2), lineWidth: 0.5)
        )
        .cornerRadius(6)
        .padding(.horizontal, 10)
        .padding(.top, 8)
    }

    // MARK: - Live Transcript Panel

    private var liveTranscriptPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Live transcript")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 12)
                .padding(.top, 6)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(recorderStore.liveSegmentsTail, id: \.start) { segment in
                            liveSegmentRow(segment)
                                .id(segment.start)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 200)
                .onChange(of: recorderStore.liveSegmentsTail.count) { _, _ in
                    if let last = recorderStore.liveSegmentsTail.last {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(last.start, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .background(Color.primary.opacity(0.03))
    }

    private func liveSegmentRow(_ segment: TranscriptSegment) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(formatSegmentTime(segment.start))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 36, alignment: .leading)

            speakerChip(segment.speaker)

            Text(segment.text)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func speakerChip(_ speaker: String?) -> some View {
        let color: Color = {
            switch speaker?.lowercased() {
            case "mic": return .green
            case "system": return .blue
            default: return .gray
            }
        }()
        let text = speaker ?? "?"
        return Text(text)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.85))
            .cornerRadius(3)
            .frame(minWidth: 32, alignment: .leading)
    }

    // MARK: - Live Summary Section

    private var liveSummarySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    summaryExpanded.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Text("Summary")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Image(systemName: summaryExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.top, 6)

            summaryContent
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
        }
        .background(Color.primary.opacity(0.03))
    }

    @ViewBuilder
    private var summaryContent: some View {
        if let live = recorderStore.liveSummary {
            if live.runningBullets.isEmpty {
                Text("Building summary\u{2026}")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else if summaryExpanded {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(live.runningBullets.enumerated()), id: \.offset) { _, bullet in
                        bulletLine(bullet)
                    }
                    if !live.windows.isEmpty {
                        Text("Windows")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .padding(.top, 6)
                        ForEach(Array(live.windows.enumerated()), id: \.offset) { _, window in
                            windowRow(window)
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(live.runningBullets.suffix(5).enumerated()), id: \.offset) { _, bullet in
                        bulletLine(bullet)
                    }
                }
            }
        }
    }

    private func bulletLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("\u{2022}")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func windowRow(_ window: WindowSummary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text("\(formatSegmentTime(window.startOffset)) - \(formatSegmentTime(window.endOffset))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                ForEach(window.speakersPresent, id: \.self) { sp in
                    speakerChip(sp)
                }
            }
            ForEach(Array(window.bullets.enumerated()), id: \.offset) { _, b in
                bulletLine(b)
            }
        }
        .padding(.vertical, 3)
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
        List {
            ForEach(recorderStore.todayRecordings) { recording in
                recordingRow(recording)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.visible)
            }
        }
        .listStyle(.plain)
    }

    private func recordingRow(_ recording: Recording) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)

                VStack(alignment: .leading, spacing: 2) {
                    if renamingId == recording.id {
                        TextField("Name", text: $renameText, onCommit: {
                            let name = renameText.trimmingCharacters(in: .whitespaces)
                            if !name.isEmpty {
                                _ = recorderStore.renameRecording(id: recording.id.uuidString, name: name)
                            }
                            renamingId = nil
                        })
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, weight: .medium))
                        .frame(maxWidth: 160)
                        .onExitCommand { renamingId = nil }
                    } else {
                        HStack(spacing: 4) {
                            Button {
                                renameText = recording.name ?? ""
                                renamingId = recording.id
                            } label: {
                                Text(recording.name ?? formatTime(recording.startedAt))
                                    .font(.system(size: 12, weight: .medium))
                                    .underline(false)
                            }
                            .buttonStyle(.plain)

                            if recording.name != nil {
                                Text(formatTime(recording.startedAt))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }

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

                transcriptionButton(for: recording)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            // Inline transcript viewer
            if expandedTranscriptId == recording.id {
                transcriptView(for: recording)
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                _ = recorderStore.deleteRecording(id: recording.id.uuidString)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Transcription Button

    @ViewBuilder
    private func transcriptionButton(for recording: Recording) -> some View {
        let isThisTranscribing = recorderStore.isTranscribing
            && recorderStore.transcribingRecordingId == recording.id

        if isThisTranscribing {
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.small)
                Text(recorderStore.transcriptionProgress)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } else if recorderStore.hasTranscript(for: recording) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if expandedTranscriptId == recording.id {
                        expandedTranscriptId = nil
                    } else {
                        expandedTranscriptId = recording.id
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: expandedTranscriptId == recording.id
                          ? "chevron.up" : "text.bubble.fill")
                        .font(.system(size: 10))
                    Text(expandedTranscriptId == recording.id ? "Hide" : "View")
                        .font(.caption2)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)
        } else {
            Button {
                Task {
                    _ = await recorderStore.transcribe(recordingId: recording.id.uuidString)
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 10))
                    Text("Transcribe")
                        .font(.caption2)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(recorderStore.isTranscribing)
        }
    }

    // MARK: - Transcript Viewer

    private func transcriptView(for recording: Recording) -> some View {
        Group {
            if let transcript = recorderStore.loadTranscript(for: recording) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(
                            Array(transcript.segments.enumerated()), id: \.offset
                        ) { _, segment in
                            transcriptSegmentRow(segment)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .frame(maxHeight: 160)
            } else {
                Text("Could not load transcript")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
            }
        }
        .background(Color.primary.opacity(0.03))
    }

    private func transcriptSegmentRow(_ segment: TranscriptSegment) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(formatSegmentTime(segment.start) + "-" + formatSegmentTime(segment.end))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 72, alignment: .leading)

            if let speaker = segment.speaker {
                Text(speaker)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(speakerColor(speaker))
                    .frame(width: 38, alignment: .leading)
            }

            Text(segment.text)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func speakerColor(_ speaker: String) -> Color {
        switch speaker.lowercased() {
        case "system": .blue
        case "mic": .green
        default: .orange
        }
    }

    private func formatSegmentTime(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
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
