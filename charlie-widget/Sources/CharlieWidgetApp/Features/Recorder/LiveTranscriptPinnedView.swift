import SwiftUI

/// Content view for the pinned floating transcript panel.
/// Stays observational of `RecorderStore` via Swift Observation.
struct LiveTranscriptPinnedView: View {

    var recorderStore: RecorderStore

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            contentArea
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            liveIndicator
            Text("Live transcript")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
            Text("\(recorderStore.liveSegments.count) seg")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var liveIndicator: some View {
        if recorderStore.isLiveTranscribing {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
                .modifier(PulseModifier())
        } else {
            Circle()
                .fill(Color.gray.opacity(0.4))
                .frame(width: 8, height: 8)
        }
    }

    // MARK: - Content area

    @ViewBuilder
    private var contentArea: some View {
        let tail = recorderStore.liveSegmentsTail
        if tail.isEmpty {
            emptyState
        } else {
            transcriptScroll(tail)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Spacer()
            if recorderStore.isLiveTranscribing {
                ProgressView().controlSize(.small)
                Text("Listening\u{2026}")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else if recorderStore.state == .recording {
                Text("Live transcription disabled")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "waveform")
                    .font(.system(size: 28))
                    .foregroundStyle(.tertiary)
                Text("Start recording to see live transcript")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func transcriptScroll(_ tail: [TranscriptSegment]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(tail, id: \.start) { segment in
                        pinnedSegmentRow(segment).id(segment.start)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .onChange(of: tail.count) { _, _ in
                if let last = tail.last {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(last.start, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func pinnedSegmentRow(_ segment: TranscriptSegment) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(formatSegmentTime(segment.start))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 38, alignment: .leading)

            speakerChip(segment.speaker)

            Text(segment.text)
                .font(.system(size: 12))
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

    private func formatSegmentTime(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}

// Subtle pulse for the live-indicator dot while transcribing.
private struct PulseModifier: ViewModifier {
    @State private var pulse = false
    func body(content: Content) -> some View {
        content
            .opacity(pulse ? 0.4 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}
