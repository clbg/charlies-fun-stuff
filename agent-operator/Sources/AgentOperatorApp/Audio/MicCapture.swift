import AVFoundation

// MARK: - MicCaptureDelegate

/// Receives chunks of 16 kHz mono Float32 audio from `MicCapture`.
protocol MicCaptureDelegate: AnyObject, Sendable {
    func didCaptureMic(samples: [Float])
}

// MARK: - MicCapture

/// Captures microphone input via `AVAudioEngine`, converts to 16 kHz mono
/// Float32, and forwards chunks to a delegate.
///
/// Designed for macOS 14+ smoke-testing of the STT pipeline without
/// Asterisk/SIP infrastructure.
actor MicCapture {

    // MARK: - Constants

    /// Target sample rate that SpeechRecognizer expects.
    private static let targetSampleRate: Double = 16_000

    // MARK: - State

    private let engine = AVAudioEngine()
    private var isRunning = false

    /// Weak-ish delegate reference. Stored as `nonisolated(unsafe)` because
    /// the delegate conformance requires `Sendable` and we only read/write
    /// it from actor-isolated methods.
    nonisolated(unsafe) private weak var delegate: MicCaptureDelegate?

    // MARK: - Configuration

    func setDelegate(_ delegate: MicCaptureDelegate?) {
        self.delegate = delegate
    }

    // MARK: - Lifecycle

    /// Begin capturing from the default input device.
    ///
    /// Audio is converted to 16 kHz mono Float32 and forwarded to the
    /// delegate via `didCaptureMic(samples:)`.
    func start() throws {
        guard !isRunning else { return }

        let inputNode = engine.inputNode
        let hwFormat = inputNode.outputFormat(forBus: 0)

        // Build target format: 16 kHz, mono, Float32.
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            fatalError("[MicCapture] Failed to create target AVAudioFormat")
        }

        // If the hardware format already matches we can skip conversion.
        let needsConversion = hwFormat.sampleRate != Self.targetSampleRate
            || hwFormat.channelCount != 1

        let converter: AVAudioConverter?
        if needsConversion {
            converter = AVAudioConverter(from: hwFormat, to: targetFormat)
        } else {
            converter = nil
        }

        let capturedDelegate = delegate

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { buffer, _ in
            let samples: [Float]

            if let converter {
                // Compute output frame count proportional to rate change.
                let ratio = Self.targetSampleRate / hwFormat.sampleRate
                let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)

                guard let outputBuffer = AVAudioPCMBuffer(
                    pcmFormat: targetFormat,
                    frameCapacity: outputFrameCount
                ) else { return }

                var error: NSError?
                let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
                    outStatus.pointee = .haveData
                    return buffer
                }
                guard status != .error, error == nil else { return }

                let count = Int(outputBuffer.frameLength)
                guard let channelData = outputBuffer.floatChannelData, count > 0 else { return }
                samples = Array(UnsafeBufferPointer(start: channelData[0], count: count))
            } else {
                let count = Int(buffer.frameLength)
                guard let channelData = buffer.floatChannelData, count > 0 else { return }
                samples = Array(UnsafeBufferPointer(start: channelData[0], count: count))
            }

            capturedDelegate?.didCaptureMic(samples: samples)
        }

        engine.prepare()
        try engine.start()
        isRunning = true
        print("[MicCapture] Started — \(hwFormat.sampleRate) Hz \(hwFormat.channelCount)ch → 16 kHz mono")
    }

    /// Stop capturing and remove the tap.
    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        print("[MicCapture] Stopped")
    }
}
