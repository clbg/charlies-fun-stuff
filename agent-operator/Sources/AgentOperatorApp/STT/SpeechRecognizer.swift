@preconcurrency import WhisperKit
import Foundation

// MARK: - SpeechRecognizer

/// Accumulates 16 kHz float32 audio from the RTP listener and periodically
/// transcribes it using WhisperKit (on-device Whisper inference).
actor SpeechRecognizer {

    // MARK: - Constants

    /// 16 kHz sample rate expected from RTPListener.
    private static let sampleRate = 16_000

    /// Minimum samples before transcription is attempted (1.6 s at 16 kHz).
    private static let minSamples = 25_600

    /// Noise / silence markers injected by Whisper.
    private static let noiseMarkers: Set<String> = [
        "[BLANK_AUDIO]", "(BLANK_AUDIO)", "[SILENCE]", "(SILENCE)"
    ]

    // MARK: - State

    private var kit: WhisperKit?
    private var buffer: [Float] = []

    // MARK: - Lifecycle

    /// Download (if needed) and load the Whisper model.
    func initialize() async throws {
        print("[STT] Loading WhisperKit model...")

        let cachedPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/huggingface/models/argmaxinc/whisperkit-coreml/openai_whisper-large-v3-v20240930_626MB")
            .path

        if FileManager.default.fileExists(atPath: cachedPath) {
            print("[STT] Using cached model at \(cachedPath)")
            kit = try await WhisperKit(WhisperKitConfig(modelFolder: cachedPath, verbose: false))
        } else {
            kit = try await WhisperKit(model: "large-v3-v20240930_626MB", verbose: false)
        }
        print("[STT] WhisperKit ready")
    }

    /// Discard accumulated audio.
    func reset() {
        buffer.removeAll()
    }

    // MARK: - Audio accumulation

    /// Append a chunk of 16 kHz float32 PCM samples to the internal buffer.
    func appendAudio(samples: [Float]) {
        buffer.append(contentsOf: samples)
    }

    // MARK: - Transcription

    /// Transcribe the current buffer and return cleaned text, or `nil` if
    /// there is not enough audio or no speech was detected.
    ///
    /// The buffer is cleared after a successful transcription attempt
    /// regardless of whether speech was found.
    func transcribe() async throws -> String? {
        guard buffer.count >= Self.minSamples else { return nil }
        guard let kit else {
            print("[STT] WhisperKit not initialized")
            return nil
        }

        let audio = buffer
        buffer.removeAll()

        let options = DecodingOptions(
            task: .transcribe,
            language: "zh",
            wordTimestamps: false
        )

        let results = try await kit.transcribe(audioArray: audio, decodeOptions: options)

        // Combine all segment texts.
        let rawText = results.map(\.text).joined(separator: " ")
        let cleaned = Self.clean(rawText)

        if cleaned.isEmpty {
            return nil
        }

        return cleaned
    }

    // MARK: - Text cleaning

    /// Strip WhisperKit control tokens and noise markers from raw output.
    private static func clean(_ text: String) -> String {
        // Remove control tokens: <|...|>
        var result = text.replacing(#/<\|[^|]*\|>/#, with: "")

        // Remove noise markers.
        for marker in noiseMarkers {
            result = result.replacingOccurrences(of: marker, with: "")
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
