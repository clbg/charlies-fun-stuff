import Foundation

// MARK: - DiarizationError

enum DiarizationError: Error, LocalizedError {
    case noSegments
    case notImplemented(String)
    case awsError(String)

    var errorDescription: String? {
        switch self {
        case .noSegments: "No transcript segments to diarize"
        case .notImplemented(let msg): "Not yet implemented: \(msg)"
        case .awsError(let msg): "AWS Transcribe error: \(msg)"
        }
    }
}

// MARK: - DiarizationProvider Protocol

/// Protocol for speaker diarization providers.
/// Implementations take an audio file and existing transcript segments,
/// then return updated segments with speaker labels assigned.
protocol DiarizationProvider: Sendable {
    /// Diarize an audio file and return segments with speaker labels assigned.
    /// - Parameters:
    ///   - audioURL: Path to the audio file (.m4a, .wav, etc.)
    ///   - existingSegments: Transcript segments from WhisperKit (may lack speaker labels)
    /// - Returns: Updated segments with `speaker` field populated
    func diarize(audioURL: URL, existingSegments: [TranscriptSegment]) async throws -> [TranscriptSegment]
}

// MARK: - MockDiarizationProvider

/// Development/testing provider that assigns speaker labels using simple heuristics.
/// Alternates between "speaker-0" and "speaker-1" when gaps between segments
/// exceed a threshold, simulating turn-taking in a conversation.
struct MockDiarizationProvider: DiarizationProvider {

    /// Minimum gap (in seconds) between segments to trigger a speaker change.
    private let gapThreshold: Double = 1.0

    func diarize(audioURL: URL, existingSegments: [TranscriptSegment]) async throws -> [TranscriptSegment] {
        guard !existingSegments.isEmpty else {
            throw DiarizationError.noSegments
        }

        let sorted = existingSegments.sorted { $0.start < $1.start }
        var currentSpeaker = 0
        var result: [TranscriptSegment] = []

        for (index, segment) in sorted.enumerated() {
            // Check if there's a gap large enough to suggest a speaker change
            if index > 0 {
                let gap = segment.start - sorted[index - 1].end
                if gap > gapThreshold {
                    currentSpeaker = (currentSpeaker + 1) % 2
                }
            }

            let label = "speaker-\(currentSpeaker)"
            result.append(TranscriptSegment(
                start: segment.start,
                end: segment.end,
                text: segment.text,
                speaker: label,
                language: segment.language,
                translation: segment.translation
            ))
        }

        return result
    }
}

// MARK: - AWSTranscribeConfig

/// Configuration for AWS Transcribe diarization.
struct AWSTranscribeConfig: Sendable {
    /// AWS region (e.g. "us-west-2")
    let region: String
    /// S3 bucket for uploading audio files for transcription
    let s3Bucket: String
    /// S3 key prefix for uploaded audio (e.g. "diarization/")
    let s3KeyPrefix: String
    /// Maximum number of speakers to identify (2-30)
    let maxSpeakers: Int
    /// Polling interval in seconds when waiting for transcription job
    let pollInterval: TimeInterval

    init(
        region: String = "us-west-2",
        s3Bucket: String = "charlie-widget-transcribe",
        s3KeyPrefix: String = "diarization/",
        maxSpeakers: Int = 10,
        pollInterval: TimeInterval = 5.0
    ) {
        self.region = region
        self.s3Bucket = s3Bucket
        self.s3KeyPrefix = s3KeyPrefix
        self.maxSpeakers = min(max(maxSpeakers, 2), 30)
        self.pollInterval = pollInterval
    }
}

// MARK: - AWSTranscribeDiarizationProvider

/// Speaker diarization using Amazon Transcribe.
///
/// Flow (when implemented):
/// 1. Upload audio file to S3
/// 2. Start a TranscribeStreaming or batch transcription job with ShowSpeakerLabels=true
/// 3. Poll for job completion
/// 4. Parse the JSON result which includes speaker labels per segment
/// 5. Map AWS speaker labels (spk_0, spk_1, ...) back to our TranscriptSegment format
///
/// Pricing: ~$0.024/min for batch transcription with speaker diarization.
/// Supports up to 30 distinct speakers.
struct AWSTranscribeDiarizationProvider: DiarizationProvider {

    let config: AWSTranscribeConfig

    init(config: AWSTranscribeConfig = AWSTranscribeConfig()) {
        self.config = config
    }

    func diarize(audioURL: URL, existingSegments: [TranscriptSegment]) async throws -> [TranscriptSegment] {
        // Step 1: Upload audio to S3
        // - Read the audio file at audioURL
        // - Generate a unique S3 key: config.s3KeyPrefix + UUID + extension
        // - PUT the file to s3://config.s3Bucket/key using AWS SDK or presigned URL
        // - Verify upload succeeded

        // Step 2: Start transcription job
        // - Call StartTranscriptionJob with:
        //   - MediaFileUri: s3://bucket/key
        //   - Settings.ShowSpeakerLabels: true
        //   - Settings.MaxSpeakerLabels: config.maxSpeakers
        //   - LanguageCode: from existingSegments or "en-US"
        //   - OutputBucketName: config.s3Bucket

        // Step 3: Poll for completion
        // - Call GetTranscriptionJob every config.pollInterval seconds
        // - Wait until status is COMPLETED or FAILED
        // - Timeout after reasonable duration (e.g. 10 minutes)

        // Step 4: Parse results
        // - Download the JSON output from S3
        // - Extract speaker_labels.segments[] which contain:
        //   - start_time, end_time, speaker_label (spk_0, spk_1, etc.)
        //   - items[] with word-level speaker attribution

        // Step 5: Map back to TranscriptSegment
        // - For each existing segment, find the best-matching AWS segment by timestamp overlap
        // - Assign the AWS speaker label (converted from "spk_0" to "speaker-0" format)
        // - Preserve original text, timestamps, language, and translation

        // Step 6: Cleanup
        // - Delete the uploaded audio from S3
        // - Delete the transcription job output from S3

        throw DiarizationError.notImplemented(
            "AWS Transcribe diarization requires AWS SDK integration. "
            + "Configure credentials and S3 bucket, then implement the upload→transcribe→parse flow. "
            + "Region: \(config.region), Bucket: \(config.s3Bucket), MaxSpeakers: \(config.maxSpeakers)"
        )
    }
}
