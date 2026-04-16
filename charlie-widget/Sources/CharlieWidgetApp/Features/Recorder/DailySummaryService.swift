import Foundation

// MARK: - Data Models

/// A section within a daily summary representing a meeting or conversation block.
struct SummarySection: Codable, Sendable {
    let title: String
    let timeRange: String       // e.g., "09:30 - 10:15"
    let participants: [String]  // speaker labels if available
    let highlights: [String]    // bullet points
}

/// A complete daily summary generated from all recordings in a day.
struct DailySummary: Codable, Sendable {
    let date: Date
    let totalRecordingMinutes: Double
    let segments: [SummarySection]   // key topics/meetings with bullet points
    let actionItems: [String]        // extracted action items
    let rawPrompt: String            // the prompt sent to the LLM (for debugging)
}

// MARK: - SummaryProvider Protocol

/// Abstraction for generating a daily summary from transcripts.
protocol SummaryProvider: Sendable {
    func summarize(
        transcripts: [(recording: Recording, transcript: Transcript)],
        date: Date
    ) async throws -> DailySummary
}

// MARK: - Mock Provider

/// Returns a realistic-looking mock summary derived from transcript content.
/// No LLM needed -- useful for development and testing.
struct MockSummaryProvider: SummaryProvider {

    func summarize(
        transcripts: [(recording: Recording, transcript: Transcript)],
        date: Date
    ) async throws -> DailySummary {
        guard !transcripts.isEmpty else {
            return DailySummary(
                date: date,
                totalRecordingMinutes: 0,
                segments: [],
                actionItems: ["No recordings found for this date."],
                rawPrompt: "(mock provider -- no prompt sent)"
            )
        }

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"

        var totalMinutes: Double = 0
        var sections: [SummarySection] = []

        for (recording, transcript) in transcripts {
            let duration = recording.durationSeconds ?? 0
            totalMinutes += duration / 60.0

            let startTime = timeFormatter.string(from: recording.startedAt)
            let endTime: String
            if let ended = recording.endedAt {
                endTime = timeFormatter.string(from: ended)
            } else {
                // Estimate from duration
                let est = recording.startedAt.addingTimeInterval(duration)
                endTime = timeFormatter.string(from: est)
            }

            // Gather unique speakers
            let speakers = Array(
                Set(transcript.segments.compactMap(\.speaker))
            ).sorted()

            // Extract a few text snippets as highlights (first, middle, last non-empty)
            let texts = transcript.segments.map(\.text).filter { !$0.isEmpty }
            var highlights: [String] = []
            if let first = texts.first {
                highlights.append(truncate(first, maxLength: 120))
            }
            if texts.count > 2 {
                let mid = texts[texts.count / 2]
                highlights.append(truncate(mid, maxLength: 120))
            }
            if texts.count > 1, let last = texts.last {
                highlights.append(truncate(last, maxLength: 120))
            }
            if highlights.isEmpty {
                highlights.append("(no transcript text)")
            }

            let title = "Recording at \(startTime)"
            sections.append(SummarySection(
                title: title,
                timeRange: "\(startTime) - \(endTime)",
                participants: speakers,
                highlights: highlights
            ))
        }

        // Generate mock action items from the last few segments
        let allTexts = transcripts.flatMap { $0.transcript.segments.map(\.text) }
        var actionItems: [String] = []
        if !allTexts.isEmpty {
            actionItems.append("Review discussion points from today's \(transcripts.count) recording(s)")
        }
        if totalMinutes > 30 {
            actionItems.append("Summarize key decisions from \(Int(totalMinutes))-minute session")
        }

        return DailySummary(
            date: date,
            totalRecordingMinutes: totalMinutes,
            segments: sections,
            actionItems: actionItems,
            rawPrompt: "(mock provider -- no prompt sent)"
        )
    }

    private func truncate(_ text: String, maxLength: Int) -> String {
        if text.count <= maxLength { return text }
        return String(text.prefix(maxLength - 3)) + "..."
    }
}

// MARK: - Bedrock Provider (Stubbed)

/// Configuration for Amazon Bedrock API calls.
struct BedrockSummaryConfig: Codable, Sendable {
    var region: String = "us-west-2"
    var modelId: String = "anthropic.claude-3-haiku-20240307-v1:0"
    var maxTokens: Int = 2048
}

/// Will use Amazon Bedrock Claude Haiku for real summarization (~$0.04/day).
/// Currently stubbed -- the prompt template is fully defined for future implementation.
struct BedrockSummaryProvider: SummaryProvider {

    let config: BedrockSummaryConfig

    init(config: BedrockSummaryConfig = BedrockSummaryConfig()) {
        self.config = config
    }

    func summarize(
        transcripts: [(recording: Recording, transcript: Transcript)],
        date: Date
    ) async throws -> DailySummary {
        let prompt = buildPrompt(transcripts: transcripts, date: date)

        // TODO: Implement Bedrock InvokeModel API call
        // 1. Sign request with SigV4 using `ada` credentials
        // 2. POST to bedrock-runtime.<region>.amazonaws.com
        // 3. Parse Claude response JSON
        // 4. Map structured output to DailySummary

        throw SummaryError.notImplemented(
            "BedrockSummaryProvider is not yet implemented. Prompt prepared (\(prompt.count) chars)."
        )
    }

    // MARK: - Prompt Template

    /// Build the full prompt that combines all transcripts into a structured summary request.
    func buildPrompt(
        transcripts: [(recording: Recording, transcript: Transcript)],
        date: Date
    ) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateStr = dateFormatter.string(from: date)

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss"

        var transcriptBlocks: [String] = []
        for (index, (recording, transcript)) in transcripts.enumerated() {
            let startTime = timeFormatter.string(from: recording.startedAt)
            let durationMin = (recording.durationSeconds ?? 0) / 60.0
            let source = recording.source.rawValue

            var lines: [String] = []
            lines.append("=== Recording \(index + 1): \(startTime) (\(String(format: "%.1f", durationMin)) min, source: \(source)) ===")

            for segment in transcript.segments {
                let ts = formatTimestamp(segment.start)
                let speaker = segment.speaker.map { "[\($0)] " } ?? ""
                let lang = segment.language != "en" ? " (\(segment.language))" : ""
                lines.append("[\(ts)] \(speaker)\(segment.text)\(lang)")
                if let translation = segment.translation {
                    lines.append("  -> \(translation)")
                }
            }

            transcriptBlocks.append(lines.joined(separator: "\n"))
        }

        let allTranscripts = transcriptBlocks.joined(separator: "\n\n")

        return """
        You are an executive assistant summarizing a day's audio recordings. \
        Today is \(dateStr). Below are transcripts from \(transcripts.count) recording(s) \
        captured throughout the day.

        ## Instructions

        Analyze all transcripts and produce a structured JSON summary with exactly these fields:

        1. **segments**: Group the content by meeting, conversation, or topic block. For each:
           - `title`: A concise descriptive title (not just "Recording 1")
           - `timeRange`: Start and end time (e.g., "09:30 - 10:15")
           - `participants`: List of speaker labels present (e.g., ["mic", "system"])
           - `highlights`: 3-5 bullet points of key discussion points

        2. **actionItems**: Extract all action items, to-dos, follow-ups, and commitments \
        mentioned across all recordings. Each should be a clear, actionable sentence.

        3. **totalRecordingMinutes**: Sum of all recording durations in minutes.

        ## Guidelines

        - If content spans multiple languages, note the language in highlights and \
        translate key points to English.
        - If speakers are labeled "system" and "mic", "system" is typically the remote \
        participant(s) and "mic" is the local user.
        - Group related recordings that appear to be the same meeting/conversation.
        - For action items, attribute them to a speaker when possible \
        (e.g., "[mic] Follow up with design team").
        - Note key decisions explicitly (prefix with "DECISION:").
        - If transcript quality is poor or contains artifacts, note this rather than guessing.

        ## Output Format

        Respond with ONLY valid JSON matching this structure (no markdown fences):
        {
          "segments": [
            {
              "title": "...",
              "timeRange": "...",
              "participants": ["..."],
              "highlights": ["..."]
            }
          ],
          "actionItems": ["..."],
          "totalRecordingMinutes": 0.0
        }

        ## Transcripts

        \(allTranscripts)
        """
    }

    private func formatTimestamp(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - Errors

enum SummaryError: Error, LocalizedError {
    case noTranscriptsFound
    case notImplemented(String)
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .noTranscriptsFound:
            "No transcript files found for this date"
        case .notImplemented(let msg):
            msg
        case .decodingFailed(let msg):
            "Failed to decode summary: \(msg)"
        }
    }
}
