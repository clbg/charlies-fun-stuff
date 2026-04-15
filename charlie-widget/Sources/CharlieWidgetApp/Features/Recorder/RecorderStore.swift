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

    // MARK: - Private

    private let captureManager = AudioCaptureManager()
    private var durationTimer: Task<Void, Never>?

    // MARK: - Init

    init() {
        loadTodayRecordings()
    }

    // MARK: - Public API

    func startRecording(source: AudioSource = .systemAndMic) async {
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

            let ext = (source == .micOnly) ? "wav" : "m4a"
            let audioURL = dayDir.appendingPathComponent("\(stem).\(ext)")

            let recording = Recording(
                id: UUID(),
                startedAt: now,
                sampleRate: 16000,
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
