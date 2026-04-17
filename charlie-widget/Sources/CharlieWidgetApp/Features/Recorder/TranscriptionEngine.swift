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
    /// Capped at `maxInMemorySegments`; older segments are trimmed from the front
    /// (they're still on disk in the `.transcript.partial` file).
    private(set) var liveSegments: [TranscriptSegment] = []

    /// Total number of segments committed this session (never trimmed).
    private(set) var totalLiveSegmentCount: Int = 0

    /// Whether live (streaming) transcription is active.
    private(set) var isLiveTranscribing = false

    /// The current partial text being transcribed (latest chunk, may change).
    private(set) var livePartialText: String = ""

    /// Called on the main actor with each batch of newly-committed segments.
    /// Consumers: LiveTranscriptWriter (crash recovery), RollingSummarizer.
    var onSegmentsCommitted: (@MainActor ([TranscriptSegment]) -> Void)?

    private var whisperKit: WhisperKit?

    /// Model to use. "small" for dev, "large-v3-v20240930_626MB" for production.
    private let modelName = "large-v3-v20240930_626MB"

    // Per-speaker live buffers — audio threads feed via nonisolated feedAudioBuffer(_:speaker:).
    // Each speaker's samples are transcribed independently so dual-track speaker attribution is preserved.
    private let liveBuffers = OSAllocatedUnfairLock(initialState: [String: LiveBufferState]())

    private struct LiveBufferState {
        var samples: [Float] = []
        var ingestedSampleCount: Int64 = 0  // cumulative samples seen for this speaker
    }

    private var liveTranscriptionTask: Task<Void, Never>?

    /// Cap on segments kept in RAM. Older ones are trimmed; disk copy is authoritative.
    private let maxInMemorySegments = 500

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

    /// Start live transcription. Call `feedAudioBuffer(_:speaker:)` to push audio samples.
    func startLiveTranscription() async throws {
        guard !isLiveTranscribing else { return }
        try await ensureLoaded()

        liveSegments = []
        totalLiveSegmentCount = 0
        livePartialText = ""
        liveBuffers.withLock { $0 = [:] }
        isLiveTranscribing = true

        // Start a background loop that periodically transcribes buffered audio
        liveTranscriptionTask = Task { [weak self] in
            await self?.liveTranscriptionLoop()
        }
        NSLog("[TranscriptionEngine] live transcription started")
    }

    /// Stop live transcription and transcribe any remaining audio.
    /// Does NOT cancel the live task — cancellation would propagate into
    /// the in-flight WhisperKit transcribe and throw CancellationError,
    /// losing the chunk. Instead we flip the flag and let the loop exit.
    func stopLiveTranscription() async {
        guard isLiveTranscribing else { return }
        isLiveTranscribing = false

        // Wait for the loop task to finish naturally (it sleeps up to 500ms then checks the flag)
        await liveTranscriptionTask?.value
        liveTranscriptionTask = nil

        // Flush any remaining buffered audio for every speaker (main-actor call, not cancellable)
        let remainingSpeakers = liveBuffers.withLock { Array($0.keys) }
        for speaker in remainingSpeakers {
            await transcribeLiveChunk(speaker: speaker, force: true)
        }
        livePartialText = ""
        NSLog("[TranscriptionEngine] live transcription stopped, total segments: \(totalLiveSegmentCount)")
    }

    /// Feed raw PCM float32 audio samples (16kHz mono) for live transcription.
    /// Called from audio capture callbacks. Thread-safe.
    nonisolated func feedAudioBuffer(_ samples: [Float], speaker: String) {
        liveBuffers.withLock { buffers in
            var state = buffers[speaker] ?? LiveBufferState()
            state.samples.append(contentsOf: samples)
            state.ingestedSampleCount += Int64(samples.count)
            buffers[speaker] = state
        }
    }

    private func liveTranscriptionLoop() async {
        let chunkSampleCount = Int(liveChunkSeconds * Self.whisperSampleRate)

        while !Task.isCancelled && isLiveTranscribing {
            try? await Task.sleep(for: .milliseconds(500))

            // Snapshot speakers whose buffers have enough audio to transcribe
            let readySpeakers = liveBuffers.withLock { buffers in
                buffers.compactMap { (key, state) in
                    state.samples.count >= chunkSampleCount ? key : nil
                }
            }
            for speaker in readySpeakers {
                await transcribeLiveChunk(speaker: speaker, force: false)
            }
        }
    }

    /// Transcribe whatever is currently buffered for the given speaker.
    /// Uses sample-count-based timestamps to avoid drift under backpressure.
    private func transcribeLiveChunk(speaker: String, force: Bool) async {
        // Drain buffer + snapshot ingestedSampleCount atomically
        let (samples, endSampleCount) = liveBuffers.withLock { buffers -> ([Float], Int64) in
            guard var state = buffers[speaker] else { return ([], 0) }
            let drained = state.samples
            let count = state.ingestedSampleCount
            state.samples = []
            buffers[speaker] = state
            return (drained, count)
        }

        // Require a minimum chunk size unless forcing (end-of-recording flush)
        let minFrames = force ? 1 : Int(liveChunkSeconds * Self.whisperSampleRate / 2)
        guard samples.count >= minFrames, let kit = whisperKit else { return }

        // Chunk start time: (ingestedBeforeThisChunk) / sampleRate
        // = (totalIngested - chunkLength) / sampleRate
        let startSampleCount = endSampleCount - Int64(samples.count)
        let chunkStartTime = Double(startSampleCount) / Self.whisperSampleRate

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
                        start: chunkStartTime + Double(seg.start),
                        end: chunkStartTime + Double(seg.end),
                        text: cleaned,
                        speaker: speaker,
                        language: language,
                        translation: nil
                    )
                }
            }

            if !newSegments.isEmpty {
                liveSegments.append(contentsOf: newSegments)
                totalLiveSegmentCount += newSegments.count
                // Trim in-memory ring so long recordings don't grow unbounded
                if liveSegments.count > maxInMemorySegments {
                    let drop = liveSegments.count - maxInMemorySegments
                    liveSegments.removeFirst(drop)
                    NSLog("[TranscriptionEngine] trimmed \(drop) older segments from memory")
                }
                livePartialText = ""
                onSegmentsCommitted?(newSegments)
            }
        } catch {
            NSLog("[TranscriptionEngine] live chunk transcription error (speaker=\(speaker)): \(error)")
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
