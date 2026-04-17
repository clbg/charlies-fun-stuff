import Foundation

// MARK: - AudioBridge

/// Bridges `MicCaptureDelegate` callbacks to a `SpeechRecognizer` actor.
///
/// Each audio chunk captured by `MicCapture` is forwarded to the recognizer
/// via an unstructured `Task` so the synchronous delegate callback doesn't
/// block.
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

// MARK: - ListenService

/// Orchestrates the listen-transcribe-ask cycle, updating `AppState` at each
/// stage so the menu-bar UI stays in sync.
@MainActor
final class ListenService {

    let appState: AppState

    private var listenTask: Task<Void, Never>?

    init(appState: AppState) {
        self.appState = appState
    }

    // MARK: - Public API

    /// Toggle between listening and idle. If already listening, cancel; if
    /// idle, start a new listen cycle. No-op in other states.
    func toggle() {
        if appState.status == .listening {
            cancel()
        } else if appState.status == .idle {
            startListening()
        }
    }

    /// Begin a full listen-transcribe-ask cycle.
    func startListening() {
        listenTask = Task {
            appState.status = .listening
            appState.lastError = nil

            do {
                // 1. Initialize WhisperKit.
                let recognizer = SpeechRecognizer()
                try await recognizer.initialize()

                // 2. Capture microphone audio.
                let capture = MicCapture()
                let bridge = AudioBridge(speechRecognizer: recognizer)
                await capture.setDelegate(bridge)
                try await capture.start()

                try await Task.sleep(nanoseconds: UInt64(appState.listenSeconds) * 1_000_000_000)
                await capture.stop()

                // 3. Transcribe.
                appState.status = .transcribing
                guard let text = try await recognizer.transcribe() else {
                    appState.status = .idle
                    return
                }

                // 4. Ask Claude.
                appState.status = .askingClaude
                let claude = ClaudeClient()
                let answer = try await claude.ask(text)

                // 5. Store result.
                appState.addResult(question: text, answer: answer)
                appState.status = .idle

            } catch is CancellationError {
                // Graceful cancellation — no error state needed.
                appState.status = .idle
            } catch {
                appState.lastError = error.localizedDescription
                appState.status = .error
                // Auto-recover to idle after 3 seconds.
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                appState.status = .idle
            }
        }
    }

    /// Cancel any in-progress listen cycle and reset to idle.
    func cancel() {
        listenTask?.cancel()
        listenTask = nil
        appState.status = .idle
    }
}
