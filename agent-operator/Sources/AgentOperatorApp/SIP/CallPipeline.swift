import Foundation

// MARK: - RTPListener delegate helper

/// Extension to set the delegate on the actor from outside.
/// Actor-isolated methods added in the same module can access the property.
extension RTPListener {
    func setAudioDelegate(_ delegate: RTPAudioDelegate?) {
        self.delegate = delegate
    }
}

// MARK: - CallPipeline

/// Orchestrator that wires together the full voice-agent pipeline:
///
///   Phone -> Asterisk/ARI -> RTP (u-law) -> RTPListener (16kHz float32)
///     -> SpeechRecognizer (WhisperKit) -> ClaudeClient -> stdout
///
/// Implements `ARIDelegate` to react to call lifecycle events and
/// `RTPAudioDelegate` to feed audio into the speech recognizer.
final class CallPipeline: Sendable {

    // MARK: - Components

    private let ariClient: ARIClient
    private let rtpListener: RTPListener
    private let speechRecognizer: SpeechRecognizer
    private let claudeClient: ClaudeClient

    /// Interval between transcription attempts (seconds).
    private let transcriptionInterval: TimeInterval

    /// Handle for the background transcription loop task.
    private let loopHandle = LoopHandle()

    /// Mutable state behind a lock for `Sendable` compliance.
    private final class LoopHandle: @unchecked Sendable {
        private let lock = NSLock()
        private var _task: Task<Void, Never>?

        var task: Task<Void, Never>? {
            get { lock.withLock { _task } }
            set { lock.withLock { _task = newValue } }
        }
    }

    // MARK: - Init

    init(
        ariConfig: ARIClient.Config = .local,
        rtpPort: UInt16 = 7078,
        transcriptionInterval: TimeInterval = 5
    ) {
        self.ariClient = ARIClient(config: ariConfig)
        self.rtpListener = RTPListener(port: rtpPort)
        self.speechRecognizer = SpeechRecognizer()
        self.claudeClient = ClaudeClient()
        self.transcriptionInterval = transcriptionInterval
    }

    // MARK: - Lifecycle

    /// Connect to Asterisk ARI and begin listening for calls.
    func start() async {
        ariClient.delegate = self
        await rtpListener.setAudioDelegate(self)
        ariClient.connect()
        print("[Pipeline] Started — waiting for calls")
    }

    /// Tear down all components.
    func stop() async {
        loopHandle.task?.cancel()
        loopHandle.task = nil
        ariClient.disconnect()
        await rtpListener.stop()
        await speechRecognizer.reset()
        print("[Pipeline] Stopped")
    }

    // MARK: - Transcription loop

    /// Periodically drain the speech buffer, transcribe, and send to Claude.
    private func startTranscriptionLoop() {
        loopHandle.task = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(self.transcriptionInterval * 1_000_000_000))
                guard !Task.isCancelled else { break }

                do {
                    if let text = try await self.speechRecognizer.transcribe() {
                        print("[STT] Recognized: \(text)")
                        let response = try await self.claudeClient.ask(text)
                        print("[Claude] \(response)")
                    }
                } catch {
                    print("[Pipeline] Transcription/Claude error: \(error)")
                }
            }
        }
    }

    private func stopTranscriptionLoop() {
        loopHandle.task?.cancel()
        loopHandle.task = nil
    }
}

// MARK: - ARIDelegate

extension CallPipeline: ARIDelegate {

    func callStarted(channelId: String) {
        print("[Pipeline] Call started — channel \(channelId)")

        Task {
            // Start RTP listener to receive audio.
            do {
                try await rtpListener.start()
            } catch {
                print("[Pipeline] Failed to start RTP listener: \(error)")
            }

            // Initialize WhisperKit (downloads model on first run).
            do {
                try await speechRecognizer.initialize()
            } catch {
                print("[Pipeline] Failed to initialize WhisperKit: \(error)")
            }

            // Begin periodic transcription.
            startTranscriptionLoop()
        }
    }

    func callEnded(channelId: String) {
        print("[Pipeline] Call ended — channel \(channelId)")

        Task {
            stopTranscriptionLoop()
            await rtpListener.stop()
            await speechRecognizer.reset()
        }
    }
}

// MARK: - RTPAudioDelegate

extension CallPipeline: RTPAudioDelegate {

    func didReceiveAudio(samples: [Float], sampleRate: Int) {
        Task {
            await speechRecognizer.appendAudio(samples: samples)
        }
    }
}
