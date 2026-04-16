import Foundation
import Observation

/// Manages speaker identity mappings from raw diarization IDs to user-friendly names.
/// Persists mappings to ~/Library/Application Support/CharlieWidget/speakers.json.
///
/// This is the foundation for voice print matching: once a speaker is identified
/// by diarization, the user can assign a friendly name that persists across recordings.
@MainActor
@Observable
final class SpeakerManager: Sendable {

    // MARK: - Types

    struct SpeakerMapping: Codable, Sendable {
        let speakerId: String
        var displayName: String
    }

    // MARK: - State

    private(set) var mappings: [String: String] = [:]  // speakerId -> displayName

    // MARK: - File path

    nonisolated static var speakersFileURL: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        return appSupport
            .appendingPathComponent("CharlieWidget", isDirectory: true)
            .appendingPathComponent("speakers.json")
    }

    // MARK: - Init

    init() {
        loadMappings()
    }

    // MARK: - Public API

    /// Returns the display name for a speaker ID, or the raw ID if no mapping exists.
    func displayName(for speakerId: String) -> String {
        mappings[speakerId] ?? speakerId
    }

    /// Assign a user-friendly name to a speaker ID. Saves immediately.
    func rename(speakerId: String, to name: String) {
        mappings[speakerId] = name
        saveMappings()
    }

    /// Returns all known speaker mappings as (speakerId, displayName) pairs,
    /// sorted by speaker ID for stable ordering.
    func allSpeakers() -> [SpeakerMapping] {
        mappings.map { SpeakerMapping(speakerId: $0.key, displayName: $0.value) }
            .sorted { $0.speakerId < $1.speakerId }
    }

    // MARK: - Persistence

    private func loadMappings() {
        let url = Self.speakersFileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([String: String].self, from: data)
            mappings = decoded
        } catch {
            print("[SpeakerManager] Failed to load speakers.json: \(error)")
        }
    }

    private func saveMappings() {
        let url = Self.speakersFileURL
        let dir = url.deletingLastPathComponent()

        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(mappings)
            try data.write(to: url, options: .atomic)
        } catch {
            print("[SpeakerManager] Failed to save speakers.json: \(error)")
        }
    }
}
