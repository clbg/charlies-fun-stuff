import Foundation

// MARK: - CallPipeline

/// Orchestrator that wires together the full voice-agent pipeline:
///
///   Phone -> FreeSWITCH (records to WAV) -> CHANNEL_HANGUP
///     -> WAVReader (16kHz float32) -> SpeechRecognizer (WhisperKit)
///     -> ClaudeClient -> stdout
///
/// Implements `ESLDelegate` to react to call lifecycle events.
/// When a call to extension 6000 ends, reads the recorded WAV file,
/// transcribes it via WhisperKit, and sends the text to Claude.
final class CallPipeline: Sendable {

    // MARK: - Components

    private let eslClient: ESLClient
    private let speechRecognizer: SpeechRecognizer
    private let claudeClient: ClaudeClient

    // MARK: - Init

    init(eslConfig: ESLClient.Config = .local) {
        self.eslClient = ESLClient(config: eslConfig)
        self.speechRecognizer = SpeechRecognizer()
        self.claudeClient = ClaudeClient()
    }

    // MARK: - Lifecycle

    /// Connect to FreeSWITCH ESL and begin listening for calls.
    func start() async throws {
        eslClient.delegate = self
        try await eslClient.connect()

        // Pre-initialize WhisperKit so it's ready when the first call ends.
        do {
            try await speechRecognizer.initialize()
        } catch {
            print("[Pipeline] Failed to initialize WhisperKit: \(error)")
        }

        print("[Pipeline] Started — waiting for calls on extension 6000")
    }

    /// Tear down all components.
    func stop() async {
        eslClient.disconnect()
        await speechRecognizer.reset()
        print("[Pipeline] Stopped")
    }
}

// MARK: - ESLDelegate

extension CallPipeline: ESLDelegate {

    func callStarted(channelId: String) {
        print("[Pipeline] Call started — channel \(channelId)")
        if let path = eslClient.lastRecordingPath {
            print("[Pipeline] Recording will be at: \(path)")
        }
    }

    func callEnded(channelId: String) {
        print("[Pipeline] Call ended — channel \(channelId)")

        Task {
            await processRecording()
        }
    }

    /// Read the WAV recording, transcribe with WhisperKit, and send to Claude.
    private func processRecording() async {
        guard let recordingPath = eslClient.lastRecordingPath else {
            print("[Pipeline] No recording path available")
            return
        }

        print("[Pipeline] Reading recording: \(recordingPath)")

        // Small delay to let FreeSWITCH flush the file.
        try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5 s

        do {
            // Read WAV file as 16 kHz float32 samples.
            let samples = try WAVReader.readFloat32(from: recordingPath)
            guard !samples.isEmpty else {
                print("[Pipeline] Recording is empty")
                return
            }
            print("[Pipeline] Read \(samples.count) samples (\(String(format: "%.1f", Double(samples.count) / 16_000.0))s of audio)")

            // Feed to SpeechRecognizer.
            await speechRecognizer.appendAudio(samples: samples)

            // Transcribe.
            if let text = try await speechRecognizer.transcribe() {
                print("[STT] Recognized: \(text)")

                // Send to Claude.
                let response = try await claudeClient.ask(text)
                print("[Claude] \(response)")
            } else {
                print("[Pipeline] No speech detected in recording")
            }

            // Reset the recognizer buffer for the next call.
            await speechRecognizer.reset()

        } catch {
            print("[Pipeline] Error processing recording: \(error)")
        }
    }
}
