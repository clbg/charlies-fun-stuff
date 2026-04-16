import Foundation
import Observation

@MainActor
@Observable
final class RecorderStore: Sendable {

    // MARK: - Directory

    nonisolated static var recordingsBaseURL: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        return appSupport
            .appendingPathComponent("CharlieWidget", isDirectory: true)
            .appendingPathComponent("recordings", isDirectory: true)
    }

    // MARK: - Observable State

    private(set) var state: RecorderState = .idle
    private(set) var currentRecording: Recording?
    private(set) var recordingStartTime: Date?
    private(set) var todayRecordings: [Recording] = []
    private(set) var lastError: String?
    private(set) var timerTick: UInt64 = 0

    var elapsedSeconds: TimeInterval {
        _ = timerTick
        guard let start = recordingStartTime, state == .recording else { return 0 }
        return Date().timeIntervalSince(start)
    }

    var audioLevel: Float {
        _ = timerTick  // re-evaluate with timer
        return state == .recording ? captureManager.audioLevel : 0
    }

    var captureDeviceName: String {
        state == .recording ? captureManager.captureDeviceName : ""
    }

    // Transcription state (Track A: UI support)
    private(set) var transcribingRecordingId: UUID?
    var isTranscribing: Bool { transcriptionEngine.isTranscribing }
    var transcriptionProgress: String { transcriptionEngine.progress }

    // MARK: - Private

    private let captureManager = AudioCaptureManager()
    private let transcriptionEngine = TranscriptionEngine()
    private let diarizationProvider: any DiarizationProvider = MockDiarizationProvider()
    private var durationTimer: Task<Void, Never>?

    // MARK: - Init

    init() {
        loadTodayRecordings()
    }

    // MARK: - Public API

    func startRecording(source: AudioSource = .both) async {
        guard state == .idle else {
            lastError = "Already recording"
            return
        }

        do {
            let now = Date()
            let stem = Self.filenameStem(for: now)
            let dayDir = Self.directoryURL(for: now)

            try FileManager.default.createDirectory(
                at: dayDir, withIntermediateDirectories: true)

            let ext = "m4a"
            let audioURL = dayDir.appendingPathComponent("\(stem).\(ext)")

            let recording = Recording(
                id: UUID(),
                startedAt: now,
                sampleRate: Int(AudioCaptureManager.outputSampleRate),
                source: source,
                filenameStem: stem
            )

            try await captureManager.start(source: source, outputURL: audioURL)

            currentRecording = recording
            recordingStartTime = now
            state = .recording
            lastError = nil

            saveMetadata(recording, in: dayDir)
            startDurationTimer()

        } catch {
            lastError = error.localizedDescription
            state = .idle
        }
    }

    func stopRecording() async {
        guard state == .recording else {
            lastError = "Not recording"
            return
        }

        state = .stopping
        durationTimer?.cancel()
        durationTimer = nil

        do {
            try await captureManager.stop()

            if var recording = currentRecording {
                let now = Date()
                recording.endedAt = now
                recording.durationSeconds = now.timeIntervalSince(recording.startedAt)

                let dayDir = Self.directoryURL(for: recording.startedAt)
                saveMetadata(recording, in: dayDir)
                todayRecordings.insert(recording, at: 0)
            }

        } catch {
            lastError = error.localizedDescription
        }

        state = .idle
        currentRecording = nil
        recordingStartTime = nil
    }

    // MARK: - Persistence

    private func saveMetadata(_ recording: Recording, in directory: URL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(recording)
            let url = directory.appendingPathComponent("\(recording.filenameStem).json")
            try data.write(to: url, options: .atomic)
        } catch {
            print("[RecorderStore] Failed to save metadata: \(error)")
        }
    }

    func loadTodayRecordings() {
        let dir = Self.directoryURL(for: Date())
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil)
        else {
            todayRecordings = []
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var recordings: [Recording] = []
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let recording = try? decoder.decode(Recording.self, from: data)
            else { continue }
            recordings.append(recording)
        }

        todayRecordings = recordings.sorted { $0.startedAt > $1.startedAt }
    }

    // MARK: - Delete & Rename

    func deleteRecording(id: String) -> Bool {
        guard let index = todayRecordings.firstIndex(where: { $0.id.uuidString == id }) else {
            lastError = "Recording not found"
            return false
        }
        let recording = todayRecordings[index]
        let dayDir = Self.directoryURL(for: recording.startedAt)
        let stem = recording.filenameStem

        // Remove all associated files
        for ext in ["m4a", "json", "transcript"] {
            let url = dayDir.appendingPathComponent("\(stem).\(ext)")
            try? FileManager.default.removeItem(at: url)
        }

        todayRecordings.remove(at: index)
        return true
    }

    func renameRecording(id: String, name: String) -> Bool {
        guard let index = todayRecordings.firstIndex(where: { $0.id.uuidString == id }) else {
            lastError = "Recording not found"
            return false
        }
        todayRecordings[index].name = name
        let dayDir = Self.directoryURL(for: todayRecordings[index].startedAt)
        saveMetadata(todayRecordings[index], in: dayDir)
        return true
    }

    // MARK: - Transcription

    nonisolated static func audioURL(for recording: Recording) -> URL {
        directoryURL(for: recording.startedAt)
            .appendingPathComponent("\(recording.filenameStem).m4a")
    }

    nonisolated static func transcriptURL(for recording: Recording) -> URL {
        directoryURL(for: recording.startedAt)
            .appendingPathComponent("\(recording.filenameStem).transcript")
    }

    func hasTranscript(for recording: Recording) -> Bool {
        FileManager.default.fileExists(atPath: Self.transcriptURL(for: recording).path)
    }

    func loadTranscript(for recording: Recording) -> Transcript? {
        let url = Self.transcriptURL(for: recording)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Transcript.self, from: data)
    }

    func transcribe(recordingId: String, language: String? = nil) async -> String? {
        guard let recording = todayRecordings.first(where: { $0.id.uuidString == recordingId }) else {
            lastError = "Recording not found"
            return nil
        }

        let audioURL = Self.audioURL(for: recording)
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            lastError = "Audio file not found"
            return nil
        }

        transcribingRecordingId = recording.id

        do {
            let segments: [TranscriptSegment]
            if recording.source == .both {
                segments = try await transcriptionEngine.transcribeMultiTrack(audioURL: audioURL, language: language)
            } else {
                segments = try await transcriptionEngine.transcribe(audioURL: audioURL, language: language)
            }
            let transcript = Transcript(segments: segments)

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(transcript)
            try data.write(to: Self.transcriptURL(for: recording), options: .atomic)

            transcribingRecordingId = nil
            return segments.map(\.text).joined(separator: " ")
        } catch {
            lastError = error.localizedDescription
            transcribingRecordingId = nil
            return nil
        }
    }

    // MARK: - Diarization

    func diarize(recordingId: String) async -> String? {
        guard let recording = todayRecordings.first(where: { $0.id.uuidString == recordingId }) else {
            lastError = "Recording not found"
            return nil
        }

        let audioURL = Self.audioURL(for: recording)
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            lastError = "Audio file not found"
            return nil
        }

        let transcriptURL = Self.transcriptURL(for: recording)
        var existingSegments: [TranscriptSegment] = []
        if let data = try? Data(contentsOf: transcriptURL),
           let transcript = try? JSONDecoder().decode(Transcript.self, from: data) {
            existingSegments = transcript.segments
        }

        if existingSegments.isEmpty {
            do {
                existingSegments = try await transcriptionEngine.transcribe(audioURL: audioURL)
            } catch {
                lastError = "Transcription failed: \(error.localizedDescription)"
                return nil
            }
        }

        guard !existingSegments.isEmpty else {
            lastError = "No transcript segments to diarize"
            return nil
        }

        do {
            let diarized = try await diarizationProvider.diarize(
                audioURL: audioURL, existingSegments: existingSegments)
            let transcript = Transcript(segments: diarized)

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(transcript)
            try data.write(to: transcriptURL, options: .atomic)

            return diarized.map { "[\($0.speaker ?? "unknown")] \($0.text)" }.joined(separator: "\n")
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    // MARK: - Voice Identification

    func identify(recordingId: String) async -> String? {
        guard let recording = todayRecordings.first(where: { $0.id.uuidString == recordingId }) else {
            lastError = "Recording not found"
            return nil
        }

        let transcriptURL = Self.transcriptURL(for: recording)
        guard let data = try? Data(contentsOf: transcriptURL),
              let transcript = try? JSONDecoder().decode(Transcript.self, from: data) else {
            lastError = "No transcript found — transcribe first"
            return nil
        }

        let audioURL = Self.audioURL(for: recording)
        let pipeline = PostProcessingPipeline()
        let voicePrintStore = VoicePrintStore()

        do {
            let result = try await pipeline.process(
                segments: transcript.segments,
                audioURL: audioURL,
                enrolledProfiles: voicePrintStore.allProfiles()
            )

            let updated = Transcript(segments: result.segments)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let updatedData = try encoder.encode(updated)
            try updatedData.write(to: transcriptURL, options: .atomic)

            return result.segments.map { "[\($0.speaker ?? "unknown")] \($0.text)" }.joined(separator: "\n")
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    // MARK: - Daily Summary

    nonisolated static func dailySummaryURL(for date: Date) -> URL {
        directoryURL(for: date).appendingPathComponent("daily-summary.json")
    }

    func generateDailySummary(for date: Date, provider: some SummaryProvider = MockSummaryProvider()) async throws -> DailySummary {
        let dir = Self.directoryURL(for: date)
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            throw SummaryError.noTranscriptsFound
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var pairs: [(recording: Recording, transcript: Transcript)] = []
        for file in files where file.pathExtension == "transcript" {
            let stem = file.deletingPathExtension().lastPathComponent
            let metaURL = dir.appendingPathComponent("\(stem).json")
            guard let metaData = try? Data(contentsOf: metaURL),
                  let recording = try? decoder.decode(Recording.self, from: metaData),
                  let transcriptData = try? Data(contentsOf: file),
                  let transcript = try? JSONDecoder().decode(Transcript.self, from: transcriptData)
            else { continue }
            pairs.append((recording, transcript))
        }

        guard !pairs.isEmpty else { throw SummaryError.noTranscriptsFound }
        pairs.sort { $0.recording.startedAt < $1.recording.startedAt }

        let summary = try await provider.summarize(transcripts: pairs, date: date)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(summary)
        try data.write(to: Self.dailySummaryURL(for: date), options: .atomic)

        return summary
    }

    // MARK: - Helpers

    nonisolated static func filenameStem(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HHmmss"
        return "recording-\(formatter.string(from: date))"
    }

    nonisolated static func directoryURL(for date: Date) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return recordingsBaseURL.appendingPathComponent(
            formatter.string(from: date), isDirectory: true)
    }

    private func startDurationTimer() {
        durationTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                self?.timerTick &+= 1
            }
        }
    }
}
