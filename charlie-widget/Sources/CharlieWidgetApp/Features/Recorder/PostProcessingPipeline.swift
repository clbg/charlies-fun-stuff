import Foundation

/// Post-processes transcript segments through voice identification and translation.
///
/// Pipeline stages:
/// 1. **Voice identification**: For each unique raw speaker ID, extract a voice embedding
///    from their longest segment, then match against enrolled voice prints to replace
///    generic labels ("speaker-0") with known names ("Alice").
/// 2. **Translation**: For segments in non-target languages, run translation and fill the
///    `translation` field.
///
/// This class is standalone and does not modify RecorderStore. It takes segments in and
/// returns updated segments out, so it can be called from any context.
struct PostProcessingPipeline: Sendable {

    let voicePrintProvider: any VoicePrintProvider
    let translationProvider: any TranslationProvider
    let targetLanguage: String

    init(
        voicePrintProvider: any VoicePrintProvider = MockVoicePrintProvider(),
        translationProvider: any TranslationProvider = MockTranslationProvider(),
        targetLanguage: String = "en"
    ) {
        self.voicePrintProvider = voicePrintProvider
        self.translationProvider = translationProvider
        self.targetLanguage = targetLanguage
    }

    /// Result of the pipeline, pairing original and post-processed data.
    struct Result: Sendable {
        let segments: [TranscriptSegment]
        /// Maps raw speaker IDs to identified names (only for matched speakers).
        let speakerMapping: [String: String]
        /// Number of segments that were translated.
        let translatedCount: Int
    }

    /// Run the full post-processing pipeline on transcript segments.
    ///
    /// - Parameters:
    ///   - segments: Raw transcript segments (potentially with speaker IDs from diarization).
    ///   - audioURL: URL of the audio file (for embedding extraction).
    ///   - enrolledProfiles: Known voice print profiles to match against.
    ///   - matchThreshold: Minimum similarity score for a positive match.
    /// - Returns: Updated segments with resolved speaker names and translations.
    func process(
        segments: [TranscriptSegment],
        audioURL: URL,
        enrolledProfiles: [VoicePrintStore.VoiceProfile],
        matchThreshold: Double = 0.85
    ) async throws -> Result {

        // Stage 1: Voice identification
        let speakerMapping = try await identifySpeakers(
            segments: segments,
            audioURL: audioURL,
            enrolledProfiles: enrolledProfiles,
            threshold: matchThreshold
        )

        // Stage 2: Apply speaker names and translate
        var translatedCount = 0
        var updatedSegments: [TranscriptSegment] = []

        for segment in segments {
            let resolvedSpeaker: String?
            if let rawSpeaker = segment.speaker, let name = speakerMapping[rawSpeaker] {
                resolvedSpeaker = name
            } else {
                resolvedSpeaker = segment.speaker
            }

            var translation: String? = segment.translation
            if segment.language != targetLanguage && translation == nil {
                do {
                    translation = try await translationProvider.translate(
                        text: segment.text,
                        from: segment.language,
                        to: targetLanguage
                    )
                    translatedCount += 1
                } catch {
                    // Translation failures are non-fatal; log and continue
                    print("[PostProcessingPipeline] Translation failed for segment at \(segment.start): \(error)")
                }
            }

            let updated = TranscriptSegment(
                start: segment.start,
                end: segment.end,
                text: segment.text,
                speaker: resolvedSpeaker,
                language: segment.language,
                translation: translation
            )
            updatedSegments.append(updated)
        }

        return Result(
            segments: updatedSegments,
            speakerMapping: speakerMapping,
            translatedCount: translatedCount
        )
    }

    // MARK: - Private

    /// For each unique speaker ID, find their longest segment, extract an embedding,
    /// and try to match against enrolled profiles.
    private func identifySpeakers(
        segments: [TranscriptSegment],
        audioURL: URL,
        enrolledProfiles: [VoicePrintStore.VoiceProfile],
        threshold: Double
    ) async throws -> [String: String] {

        guard !enrolledProfiles.isEmpty else { return [:] }

        // Group segments by speaker
        var segmentsBySpeaker: [String: [TranscriptSegment]] = [:]
        for segment in segments {
            guard let speaker = segment.speaker else { continue }
            segmentsBySpeaker[speaker, default: []].append(segment)
        }

        var mapping: [String: String] = [:]

        for (rawSpeakerId, speakerSegments) in segmentsBySpeaker {
            // Pick the longest segment for embedding extraction (best signal)
            guard let longestSegment = speakerSegments.max(by: { ($0.end - $0.start) < ($1.end - $1.start) }) else {
                continue
            }

            do {
                let embedding = try await voicePrintProvider.extractEmbedding(
                    audioURL: audioURL,
                    startTime: longestSegment.start,
                    endTime: longestSegment.end
                )

                // Compare against all enrolled profiles
                var bestId: String?
                var bestScore: Double = 0

                for profile in enrolledProfiles {
                    let score = voicePrintProvider.similarity(embedding, profile.embedding)
                    if score > bestScore && score >= threshold {
                        bestScore = score
                        bestId = profile.speakerId
                    }
                }

                if let matchedName = bestId {
                    mapping[rawSpeakerId] = matchedName
                }
            } catch {
                print("[PostProcessingPipeline] Embedding extraction failed for \(rawSpeakerId): \(error)")
            }
        }

        return mapping
    }
}
