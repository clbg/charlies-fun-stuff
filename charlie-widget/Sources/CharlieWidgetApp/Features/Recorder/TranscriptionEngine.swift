@preconcurrency import WhisperKit
import Foundation

/// Offline transcription using WhisperKit (CoreML-optimized Whisper).
@MainActor
@Observable
final class TranscriptionEngine {

    private(set) var isTranscribing = false
    private(set) var progress: String = ""

    private var whisperKit: WhisperKit?

    /// Model to use. "small" for dev, "large-v3-v20240930_626MB" for production.
    private let modelName = "small"

    /// Initialize WhisperKit (downloads model on first use).
    func ensureLoaded() async throws {
        guard whisperKit == nil else { return }
        progress = "Loading model..."
        whisperKit = try await WhisperKit(model: modelName, verbose: false)
        progress = "Model loaded"
    }

    /// Transcribe an audio file and return transcript segments.
    func transcribe(audioURL: URL) async throws -> [TranscriptSegment] {
        try await ensureLoaded()
        guard let kit = whisperKit else { return [] }

        isTranscribing = true
        defer { isTranscribing = false }

        progress = "Transcribing..."
        let results = try await kit.transcribe(
            audioPath: audioURL.path,
            decodeOptions: DecodingOptions(
                task: .transcribe,
                language: nil,
                wordTimestamps: true,
                chunkingStrategy: .vad
            )
        )

        progress = "Done"

        // Convert WhisperKit segments to our model, filtering out empty/token-only segments
        let language = results.first?.language ?? "en"
        return results.flatMap { result in
            result.segments.compactMap { seg in
                let cleaned = TranscriptionEngine.cleanText(seg.text)
                guard !cleaned.isEmpty else { return nil }
                return TranscriptSegment(
                    start: Double(seg.start),
                    end: Double(seg.end),
                    text: cleaned,
                    speaker: nil,
                    language: language,
                    translation: nil
                )
            }
        }
    }

    /// Strip Whisper special tokens and noise markers from text.
    private static func cleanText(_ text: String) -> String {
        var s = text
        // Remove Whisper control tokens like <|startoftranscript|>, <|en|>, <|0.00|>, etc.
        s = s.replacingOccurrences(
            of: "<\\|[^|]*\\|>",
            with: "",
            options: .regularExpression
        )
        // Remove noise markers
        s = s.replacingOccurrences(of: "[BLANK_AUDIO]", with: "")
        s = s.replacingOccurrences(of: "[Music]", with: "")
        s = s.replacingOccurrences(of: "(music)", with: "")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Transcript Data Model

/// A single transcript segment with timestamps and optional speaker/translation.
struct TranscriptSegment: Codable, Sendable {
    let start: Double
    let end: Double
    let text: String
    let speaker: String?
    let language: String
    let translation: String?
}

/// Full transcript for a recording.
struct Transcript: Codable, Sendable {
    let segments: [TranscriptSegment]
}
