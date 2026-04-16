import Foundation

// MARK: - RecorderState

enum RecorderState: String, Codable, Sendable {
    case idle
    case recording
    case stopping
}

// MARK: - AudioSource

enum AudioSource: String, Codable, Sendable {
    case mic = "mic"
    case system = "system"
    case both = "both"
}

// Backward compat: old recordings used "mic-only" and "system+mic"
extension AudioSource {
    init(legacyRawValue: String) {
        switch legacyRawValue {
        case "mic-only": self = .mic
        case "system+mic": self = .both
        default: self = AudioSource(rawValue: legacyRawValue) ?? .both
        }
    }
}

// MARK: - RecorderError

enum RecorderError: Error, LocalizedError {
    case noDisplay
    case permissionDenied(String)
    case alreadyRecording
    case notRecording
    case assetWriterFailed(String)

    var errorDescription: String? {
        switch self {
        case .noDisplay: "No display found for screen capture"
        case .permissionDenied(let p): "\(p) permission denied. Grant in System Settings > Privacy."
        case .alreadyRecording: "Already recording"
        case .notRecording: "Not currently recording"
        case .assetWriterFailed(let msg): "Audio writer failed: \(msg)"
        }
    }
}

// MARK: - Recording

struct Recording: Identifiable, Codable, Sendable {
    let id: UUID
    let startedAt: Date
    var endedAt: Date?
    var durationSeconds: Double?
    let sampleRate: Int
    let source: AudioSource
    let filenameStem: String

    enum CodingKeys: String, CodingKey {
        case id
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case durationSeconds = "duration_seconds"
        case sampleRate = "sample_rate"
        case source
        case filenameStem = "filename_stem"
    }
}
