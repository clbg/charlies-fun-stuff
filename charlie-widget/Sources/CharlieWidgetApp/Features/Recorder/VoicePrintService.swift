import Foundation
import Observation

// MARK: - Voice Embedding

/// A voice embedding vector with an optional speaker label.
/// Represents the speaker's vocal characteristics as a fixed-length float vector.
struct VoiceEmbedding: Codable, Sendable {
    let vector: [Float]
    var speakerLabel: String?

    init(vector: [Float], speakerLabel: String? = nil) {
        self.vector = vector
        self.speakerLabel = speakerLabel
    }
}

// MARK: - VoicePrintProvider Protocol

/// Extracts voice embeddings from audio and compares them for speaker identification.
///
/// ## Future Real Implementation
///
/// The production provider will use **sherpa-onnx** with the **WeSpeaker CAM++** model (~50 MB):
///
/// - Model: `wespeaker_zh_cnceleb_cam++.onnx` (or English variant)
/// - C API: `SherpaOnnxSpeakerEmbeddingExtractor` from sherpa-onnx
/// - Flow:
///   1. Load audio segment (16kHz mono float32)
///   2. Call `SherpaOnnxSpeakerEmbeddingExtractorCreateStream()`
///   3. Feed samples via `AcceptWaveform()`
///   4. Call `Compute()` → returns 512-dim float vector
///   5. Cosine similarity between vectors for matching
/// - Threshold: ~0.85 for same-speaker, tunable per environment
/// - Cost: CPU-only, ~100ms per 5s segment on Apple Silicon
protocol VoicePrintProvider: Sendable {
    /// Extract a voice embedding from an audio segment.
    func extractEmbedding(audioURL: URL, startTime: Double, endTime: Double) async throws -> VoiceEmbedding
    /// Compare two embeddings, return similarity score (0.0 - 1.0).
    func similarity(_ a: VoiceEmbedding, _ b: VoiceEmbedding) -> Double
}

// MARK: - MockVoicePrintProvider

/// Mock provider that returns deterministic embeddings based on speaker ID.
/// Same speaker label → same embedding vector, enabling end-to-end pipeline testing
/// without sherpa-onnx.
struct MockVoicePrintProvider: VoicePrintProvider {

    /// Embedding dimension (matches WeSpeaker CAM++ output).
    private let dimension = 512

    func extractEmbedding(audioURL: URL, startTime: Double, endTime: Double) async throws -> VoiceEmbedding {
        // In mock mode, derive a pseudo-speaker from the time range.
        // Real implementation would analyze the actual audio.
        let pseudoSpeaker = "speaker-\(Int(startTime) % 4)"
        return deterministicEmbedding(for: pseudoSpeaker)
    }

    func similarity(_ a: VoiceEmbedding, _ b: VoiceEmbedding) -> Double {
        guard a.vector.count == b.vector.count, !a.vector.isEmpty else { return 0.0 }
        // Cosine similarity
        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        for i in 0..<a.vector.count {
            dot += a.vector[i] * b.vector[i]
            normA += a.vector[i] * a.vector[i]
            normB += b.vector[i] * b.vector[i]
        }
        let denom = sqrt(normA) * sqrt(normB)
        guard denom > 0 else { return 0.0 }
        return Double(dot / denom)
    }

    /// Generate a deterministic embedding from a speaker label.
    /// Uses a simple hash-based seed so the same label always produces the same vector.
    func deterministicEmbedding(for speakerLabel: String) -> VoiceEmbedding {
        var hasher = Hasher()
        hasher.combine(speakerLabel)
        // Use a fixed salt so results are stable within a process
        hasher.combine("voiceprint-salt-2024")
        var seed = UInt64(bitPattern: Int64(hasher.finalize()))

        var vector = [Float](repeating: 0, count: dimension)
        for i in 0..<dimension {
            // Simple xorshift64 PRNG for deterministic pseudo-random values
            seed ^= seed << 13
            seed ^= seed >> 7
            seed ^= seed << 17
            // Map to [-1, 1] range
            vector[i] = Float(Int64(bitPattern: seed) % 10000) / 10000.0
        }

        // Normalize to unit length
        let norm = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        if norm > 0 {
            vector = vector.map { $0 / norm }
        }

        return VoiceEmbedding(vector: vector, speakerLabel: speakerLabel)
    }
}

// MARK: - VoicePrintStore

/// Manages saved voice prints for known speakers.
/// Persists enrolled profiles to disk so they survive app restarts.
@MainActor
@Observable
final class VoicePrintStore {

    // MARK: - Types

    struct VoiceProfile: Codable, Sendable {
        let speakerId: String
        let embedding: VoiceEmbedding
        let enrolledAt: Date
    }

    // MARK: - State

    private(set) var profiles: [VoiceProfile] = []

    /// Similarity threshold for positive identification (0.0 - 1.0).
    var matchThreshold: Double = 0.85

    // MARK: - Private

    private let provider: any VoicePrintProvider
    private let storageURL: URL

    // MARK: - Init

    init(provider: any VoicePrintProvider = MockVoicePrintProvider()) {
        self.provider = provider
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        self.storageURL = appSupport
            .appendingPathComponent("CharlieWidget", isDirectory: true)
            .appendingPathComponent("voiceprints.json")
        loadProfiles()
    }

    // MARK: - Public API

    /// Enroll a speaker by saving their voice embedding.
    func enroll(speakerId: String, embedding: VoiceEmbedding) {
        var labeled = embedding
        labeled.speakerLabel = speakerId
        let profile = VoiceProfile(
            speakerId: speakerId,
            embedding: labeled,
            enrolledAt: Date()
        )
        // Replace existing profile for same speaker
        profiles.removeAll { $0.speakerId == speakerId }
        profiles.append(profile)
        saveProfiles()
    }

    /// Identify a speaker by comparing an embedding against all enrolled profiles.
    /// Returns the speaker ID of the best match above threshold, or nil.
    func identify(embedding: VoiceEmbedding, threshold: Double? = nil) -> String? {
        let thresh = threshold ?? matchThreshold
        var bestId: String?
        var bestScore: Double = 0

        for profile in profiles {
            let score = provider.similarity(embedding, profile.embedding)
            if score > bestScore && score >= thresh {
                bestScore = score
                bestId = profile.speakerId
            }
        }

        return bestId
    }

    /// Return all enrolled profiles.
    func allProfiles() -> [VoiceProfile] {
        profiles
    }

    /// Extract an embedding using the configured provider.
    func extractEmbedding(audioURL: URL, startTime: Double, endTime: Double) async throws -> VoiceEmbedding {
        try await provider.extractEmbedding(audioURL: audioURL, startTime: startTime, endTime: endTime)
    }

    // MARK: - Persistence

    private func loadProfiles() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            profiles = try decoder.decode([VoiceProfile].self, from: data)
        } catch {
            print("[VoicePrintStore] Failed to load profiles: \(error)")
        }
    }

    private func saveProfiles() {
        do {
            let dir = storageURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(profiles)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("[VoicePrintStore] Failed to save profiles: \(error)")
        }
    }
}
