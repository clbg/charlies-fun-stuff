import Foundation

// MARK: - MicPipeline

/// A simplified pipeline that bypasses Asterisk/SIP for CLI smoke testing:
///
///   Microphone → MicCapture (16 kHz mono) → SpeechRecognizer (WhisperKit)
///     → ClaudeClient → stdout
///
/// Usage:
/// ```swift
/// let pipeline = MicPipeline()
/// await pipeline.run(listenSeconds: 8)
/// ```
final class MicPipeline: Sendable {

    private let micCapture: MicCapture
    private let speechRecognizer: SpeechRecognizer
    private let claudeClient: ClaudeClient

    init() {
        self.micCapture = MicCapture()
        self.speechRecognizer = SpeechRecognizer()
        self.claudeClient = ClaudeClient()
    }

    /// Run a single listen-transcribe-ask cycle.
    ///
    /// 1. Initialize WhisperKit (downloads model on first run).
    /// 2. Capture microphone for `listenSeconds` seconds.
    /// 3. Transcribe the captured audio.
    /// 4. Send the transcription to Claude and print the response.
    ///
    /// - Parameter listenSeconds: How long to record before transcribing.
    func run(listenSeconds: Int = 8) async {
        // Wire MicCapture → SpeechRecognizer via the bridge.
        let bridge = AudioBridge(speechRecognizer: speechRecognizer)
        await micCapture.setDelegate(bridge)

        // 1. Initialize WhisperKit.
        do {
            try await speechRecognizer.initialize()
        } catch {
            print("[MicPipeline] Failed to initialize WhisperKit: \(error)")
            return
        }

        // 2. Capture microphone audio.
        print("[MicPipeline] Listening for \(listenSeconds) seconds — speak now...")
        do {
            try await micCapture.start()
        } catch {
            print("[MicPipeline] Failed to start microphone: \(error)")
            return
        }

        try? await Task.sleep(nanoseconds: UInt64(listenSeconds) * 1_000_000_000)
        await micCapture.stop()

        // 3. Transcribe.
        do {
            guard let text = try await speechRecognizer.transcribe() else {
                print("[MicPipeline] No speech detected.")
                return
            }
            print("[STT] Recognized: \(text)")

            // 4. Ask Claude.
            let response = try await claudeClient.ask(text)
            print("[Claude] \(response)")

        } catch {
            print("[MicPipeline] Error: \(error)")
        }
    }
}

// MARK: - AudioBridge

/// Bridges `MicCaptureDelegate` callbacks to the `SpeechRecognizer` actor.
private final class AudioBridge: MicCaptureDelegate, Sendable {

    private let speechRecognizer: SpeechRecognizer

    init(speechRecognizer: SpeechRecognizer) {
        self.speechRecognizer = speechRecognizer
    }

    func didCaptureMic(samples: [Float]) {
        Task {
            await speechRecognizer.appendAudio(samples: samples)
        }
    }
}
