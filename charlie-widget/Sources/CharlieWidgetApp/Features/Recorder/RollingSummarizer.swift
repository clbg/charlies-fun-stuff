import Foundation

// MARK: - Data Models

/// A single rolling-window summary flushed during a recording.
struct WindowSummary: Codable, Sendable {
    let startOffset: Double          // seconds from recording start
    let endOffset: Double
    let segmentCount: Int
    let bullets: [String]            // 2-4 bullets for this window
    let speakersPresent: [String]
}

/// Live summary persisted during a recording. Complements .transcript.partial.
struct LiveSummary: Codable, Sendable {
    let recordingId: String
    var runningBullets: [String]     // append-only key-point stream across the whole recording
    var windows: [WindowSummary]     // per-window recaps
    var lastUpdatedAt: Date
}

// MARK: - WindowSummaryProvider Protocol

/// Summarizes a single rolling window of transcript segments.
/// Default impl (Mock) extracts snippets; Bedrock variant will call Claude Haiku.
protocol WindowSummaryProvider: Sendable {
    func summarizeWindow(
        segments: [TranscriptSegment],
        priorRunningBullets: [String]
    ) async throws -> (windowBullets: [String], newRunningBullets: [String])
}

struct MockWindowSummaryProvider: WindowSummaryProvider {
    func summarizeWindow(
        segments: [TranscriptSegment],
        priorRunningBullets: [String]
    ) async throws -> (windowBullets: [String], newRunningBullets: [String]) {
        let texts = segments.map(\.text).filter { !$0.isEmpty }
        var windowBullets: [String] = []
        if let first = texts.first { windowBullets.append(Self.truncate(first, max: 140)) }
        if texts.count > 2 { windowBullets.append(Self.truncate(texts[texts.count / 2], max: 140)) }
        if texts.count > 1, let last = texts.last { windowBullets.append(Self.truncate(last, max: 140)) }
        if windowBullets.isEmpty { windowBullets.append("(no speech in window)") }

        // Append 1 new running bullet per window, tagged by start offset
        var running = priorRunningBullets
        if let startSec = segments.first?.start, let bullet = windowBullets.first {
            let m = Int(startSec) / 60
            let s = Int(startSec) % 60
            running.append(String(format: "[%02d:%02d] %@", m, s, bullet))
        }
        return (windowBullets, running)
    }

    private static func truncate(_ s: String, max: Int) -> String {
        s.count <= max ? s : String(s.prefix(max - 3)) + "..."
    }
}

// MARK: - RollingSummarizer

/// Ingests live transcript segments, decides when to flush a window summary
/// based on (speaker-change && >=90s && >=200 chars) OR a 5-minute hard ceiling,
/// and persists the resulting `LiveSummary` to disk as `{stem}.live-summary.json`.
@MainActor
final class RollingSummarizer {

    // Trigger thresholds — kept as properties for testability.
    var minIntervalSeconds: TimeInterval = 90
    var minCharsPerFlush: Int = 200
    var hardCeilingSeconds: TimeInterval = 300

    private(set) var summary: LiveSummary

    private let provider: any WindowSummaryProvider
    private let storageURL: URL
    private let recordingStart: Date

    private var pendingSegments: [TranscriptSegment] = []
    private var charsPending: Int = 0
    private var lastFlushAt: Date
    private var flushTask: Task<Void, Never>?

    init(
        recording: Recording,
        provider: any WindowSummaryProvider,
        storageURL: URL
    ) {
        self.provider = provider
        self.storageURL = storageURL
        self.recordingStart = recording.startedAt
        self.summary = LiveSummary(
            recordingId: recording.id.uuidString,
            runningBullets: [],
            windows: [],
            lastUpdatedAt: recording.startedAt
        )
        self.lastFlushAt = recording.startedAt
    }

    /// Feed newly-committed segments. Returns immediately; flush runs in background.
    func ingest(_ newSegments: [TranscriptSegment]) {
        guard !newSegments.isEmpty else { return }
        let hadSpeakerBefore = pendingSegments.last?.speaker
        pendingSegments.append(contentsOf: newSegments)
        charsPending += newSegments.reduce(0) { $0 + $1.text.count }

        // Speaker change: either inside the new batch, or vs. the last-pending segment
        let allSpeakers = pendingSegments.compactMap(\.speaker)
        let speakerChanged = Set(allSpeakers).count > 1 ||
            (hadSpeakerBefore != nil && newSegments.first?.speaker != hadSpeakerBefore)

        let elapsed = Date().timeIntervalSince(lastFlushAt)
        let shouldFlush =
            (speakerChanged && elapsed >= minIntervalSeconds && charsPending >= minCharsPerFlush)
            || elapsed >= hardCeilingSeconds

        if shouldFlush {
            scheduleFlush()
        }
    }

    /// Force-flush remaining pending segments at end of recording.
    func finalize() async {
        flushTask?.cancel()
        flushTask = nil
        if !pendingSegments.isEmpty {
            await flushNow()
        }
        persist()
    }

    // MARK: - Private

    private func scheduleFlush() {
        guard flushTask == nil else { return }  // in-flight flush
        flushTask = Task { [weak self] in
            await self?.flushNow()
            await MainActor.run { [weak self] in
                self?.flushTask = nil
            }
        }
    }

    private func flushNow() async {
        let toSummarize = pendingSegments
        let startOffset = toSummarize.first.map { $0.start } ?? 0
        let endOffset = toSummarize.last.map { $0.end } ?? startOffset
        let speakers = Array(Set(toSummarize.compactMap(\.speaker))).sorted()
        pendingSegments = []
        charsPending = 0
        lastFlushAt = Date()

        guard !toSummarize.isEmpty else { return }

        do {
            let priorBullets = summary.runningBullets
            let result = try await provider.summarizeWindow(
                segments: toSummarize,
                priorRunningBullets: priorBullets
            )
            summary.windows.append(WindowSummary(
                startOffset: startOffset,
                endOffset: endOffset,
                segmentCount: toSummarize.count,
                bullets: result.windowBullets,
                speakersPresent: speakers
            ))
            // Cap runningBullets at 50 so it doesn't grow unbounded on long recordings
            var running = result.newRunningBullets
            if running.count > 50 {
                running = Array(running.suffix(50))
            }
            summary.runningBullets = running
            summary.lastUpdatedAt = Date()
            persist()
        } catch {
            NSLog("[RollingSummarizer] flush failed: \(error)")
            // Don't drop segments — put them back for the next trigger
            pendingSegments.insert(contentsOf: toSummarize, at: 0)
            charsPending += toSummarize.reduce(0) { $0 + $1.text.count }
        }
    }

    private func persist() {
        do {
            let enc = JSONEncoder()
            enc.dateEncodingStrategy = .iso8601
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try enc.encode(summary)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            NSLog("[RollingSummarizer] persist failed: \(error)")
        }
    }
}
