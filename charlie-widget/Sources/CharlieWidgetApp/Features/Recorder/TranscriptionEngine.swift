@preconcurrency import WhisperKit
import AVFoundation
import Foundation
import os

/// Offline transcription using WhisperKit (CoreML-optimized Whisper).
@MainActor
@Observable
final class TranscriptionEngine {

    private(set) var isTranscribing = false
    private(set) var progress: String = ""

    // MARK: - Live Transcription State

    /// Accumulated live transcript segments, updated as each chunk is transcribed.
    private(set) var liveSegments: [TranscriptSegment] = []

    /// Whether live (streaming) transcription is active.
    private(set) var isLiveTranscribing = false

    /// The current partial text being transcribed (latest chunk, may change).
    private(set) var livePartialText: String = ""

    private var whisperKit: WhisperKit?

    /// Model to use. "small" for dev, "large-v3-v20240930_626MB" for production.
    private let modelName = "large-v3-v20240930_626MB"

    // Live transcription internals — buffer is accessed from audio threads via nonisolated feedAudioBuffer
    private let liveBuffer = OSAllocatedUnfairLock(initialState: [Float]())
    private var liveTranscriptionTask: Task<Void, Never>?

    /// How many seconds of audio to accumulate before transcribing a chunk.
    private let liveChunkSeconds: Double = 5.0

    /// WhisperKit expects 16kHz mono audio.
    private static let whisperSampleRate: Double = 16000

    /// Initialize WhisperKit (downloads model on first use).
    func ensureLoaded() async throws {
        guard whisperKit == nil else { return }
        progress = "Loading model..."
        whisperKit = try await WhisperKit(model: modelName, verbose: false)
        progress = "Model loaded"
    }

    // MARK: - Live Transcription

    /// Start live transcription. Call `feedAudioBuffer` to push audio samples.
    func startLiveTranscription() async throws {
        guard !isLiveTranscribing else { return }
        try await ensureLoaded()

        liveSegments = []
        livePartialText = ""
        liveBuffer.withLock { $0 = [] }
        isLiveTranscribing = true

        // Start a background loop that periodically transcribes buffered audio
        liveTranscriptionTask = Task { [weak self] in
            await self?.liveTranscriptionLoop()
        }
        NSLog("[TranscriptionEngine] live transcription started")
    }

    /// Stop live transcription and transcribe any remaining audio.
    func stopLiveTranscription() async {
        guard isLiveTranscribing else { return }
        isLiveTranscribing = false
        liveTranscriptionTask?.cancel()
        liveTranscriptionTask = nil

        // Transcribe any remaining buffered audio
        await transcribeLiveChunk()
        livePartialText = ""
        NSLog("[TranscriptionEngine] live transcription stopped, total segments: \(liveSegments.count)")
    }

    /// Feed raw PCM float32 audio samples (16kHz mono) for live transcription.
    /// Called from audio capture callbacks. Thread-safe.
    nonisolated func feedAudioBuffer(_ samples: [Float]) {
        liveBuffer.withLock { $0.append(contentsOf: samples) }
    }

    private func liveTranscriptionLoop() async {
        let chunkSampleCount = Int(liveChunkSeconds * Self.whisperSampleRate)

        while !Task.isCancelled && isLiveTranscribing {
            // Wait until we have enough audio
            try? await Task.sleep(for: .milliseconds(500))

            let bufferCount = liveBuffer.withLock { $0.count }

            if bufferCount >= chunkSampleCount {
                await transcribeLiveChunk()
            }
        }
    }

    /// Transcribe whatever is currently in the live audio buffer.
    private func transcribeLiveChunk() async {
        // Drain the buffer
        let samples = liveBuffer.withLock { buf -> [Float] in
            let s = buf; buf = []; return s
        }

        guard !samples.isEmpty, let kit = whisperKit else { return }

        // Calculate time offset for this chunk based on existing segments
        let timeOffset: Double = liveSegments.last?.end ?? 0

        do {
            let results: [TranscriptionResult] = try await kit.transcribe(
                audioArray: samples,
                decodeOptions: DecodingOptions(
                    task: .transcribe,
                    language: nil,
                    wordTimestamps: false
                )
            )

            let language = results.first?.language ?? "en"
            let newSegments: [TranscriptSegment] = results.flatMap { result in
                result.segments.compactMap { seg in
                    let cleaned = TranscriptionEngine.cleanText(seg.text)
                    guard !cleaned.isEmpty else { return nil }
                    return TranscriptSegment(
                        start: timeOffset + Double(seg.start),
                        end: timeOffset + Double(seg.end),
                        text: cleaned,
                        speaker: nil,
                        language: language,
                        translation: nil
                    )
                }
            }

            if !newSegments.isEmpty {
                liveSegments.append(contentsOf: newSegments)
                livePartialText = ""
            }
        } catch {
            NSLog("[TranscriptionEngine] live chunk transcription error: \(error)")
        }
    }

    /// Transcribe an audio file and return transcript segments.
    /// For single-track files, speaker is nil. For multi-track, call `transcribeMultiTrack` instead.
    func transcribe(audioURL: URL, speaker: String? = nil, language: String? = nil) async throws -> [TranscriptSegment] {
        try await ensureLoaded()
        guard let kit = whisperKit else { return [] }

        isTranscribing = true
        defer { isTranscribing = false }

        let results = try await kit.transcribe(
            audioPath: audioURL.path,
            decodeOptions: DecodingOptions(
                task: .transcribe,
                language: language,
                wordTimestamps: true,
                chunkingStrategy: .vad
            )
        )

        let language = results.first?.language ?? "en"
        return results.flatMap { result in
            result.segments.compactMap { seg in
                let cleaned = TranscriptionEngine.cleanText(seg.text)
                guard !cleaned.isEmpty else { return nil }
                return TranscriptSegment(
                    start: Double(seg.start),
                    end: Double(seg.end),
                    text: cleaned,
                    speaker: speaker,
                    language: language,
                    translation: nil
                )
            }
        }
    }

    /// Transcribe a multi-track .m4a by extracting each track, transcribing separately,
    /// and merging segments sorted by start time.
    func transcribeMultiTrack(audioURL: URL, language: String? = nil) async throws -> [TranscriptSegment] {
        try await ensureLoaded()

        let asset = AVURLAsset(url: audioURL)
        let tracks = asset.tracks(withMediaType: .audio)

        guard tracks.count >= 2 else {
            // Fallback to single-track transcription
            return try await transcribe(audioURL: audioURL, language: language)
        }

        let trackLabels = ["system", "mic"]
        var allSegments: [TranscriptSegment] = []

        for (index, label) in trackLabels.prefix(tracks.count).enumerated() {
            progress = "Extracting \(label) track..."

            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("transcribe-\(label)-\(UUID().uuidString).wav")

            try await extractTrack(trackIndex: index, from: audioURL, to: tempURL)
            defer { try? FileManager.default.removeItem(at: tempURL) }

            progress = "Transcribing \(label) track..."
            let segments = try await transcribe(audioURL: tempURL, speaker: label, language: language)
            allSegments.append(contentsOf: segments)
        }

        progress = "Done"
        return allSegments.sorted { $0.start < $1.start }
    }

    /// Extract a single audio track to a 16kHz mono WAV file for transcription.
    private nonisolated func extractTrack(
        trackIndex: Int, from sourceURL: URL, to outputURL: URL
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            DispatchQueue(label: "track-extract").async {
                do {
                    try? FileManager.default.removeItem(at: outputURL)

                    let asset = AVURLAsset(url: sourceURL)
                    let tracks = asset.tracks(withMediaType: .audio)
                    guard trackIndex < tracks.count else {
                        continuation.resume(throwing: RecorderError.assetWriterFailed("track \(trackIndex) not found"))
                        return
                    }

                    // Read as 16kHz mono float32 — AVAudioFile writes float PCM cleanly
                    let reader = try AVAssetReader(asset: asset)
                    let readSettings: [String: Any] = [
                        AVFormatIDKey: kAudioFormatLinearPCM,
                        AVSampleRateKey: 16000,
                        AVNumberOfChannelsKey: 1,
                        AVLinearPCMBitDepthKey: 32,
                        AVLinearPCMIsFloatKey: true,
                        AVLinearPCMIsBigEndianKey: false,
                    ]
                    let readerOutput = AVAssetReaderTrackOutput(track: tracks[trackIndex], outputSettings: readSettings)
                    reader.add(readerOutput)
                    reader.startReading()

                    let outputFormat = AVAudioFormat(
                        commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
                    let outputFile = try AVAudioFile(forWriting: outputURL, settings: outputFormat.settings)

                    while reader.status == .reading {
                        guard let sample = readerOutput.copyNextSampleBuffer() else { break }
                        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sample))
                        guard frameCount > 0,
                              let pcmBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameCount),
                              let dataBuffer = CMSampleBufferGetDataBuffer(sample)
                        else { continue }

                        pcmBuffer.frameLength = frameCount
                        var length = 0
                        var dataPointer: UnsafeMutablePointer<Int8>?
                        CMBlockBufferGetDataPointer(dataBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
                        if let src = dataPointer, let dst = pcmBuffer.floatChannelData?[0] {
                            memcpy(dst, src, min(length, Int(frameCount) * 4))
                        }

                        try outputFile.write(from: pcmBuffer)
                    }

                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
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
        // Remove bracketed/parenthesized noise markers (ASCII-only content — preserves Chinese/Japanese in brackets)
        s = s.replacingOccurrences(of: "\\[\\s*[A-Za-z_ ]+\\s*\\]", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\(\\s*[A-Za-z_ ]+\\s*\\)", with: "", options: .regularExpression)
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
