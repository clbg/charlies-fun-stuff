@preconcurrency import AVFAudio
import AVFoundation
@preconcurrency import CoreMedia
@preconcurrency import ScreenCaptureKit

// MARK: - AudioCaptureManager

final class AudioCaptureManager: @unchecked Sendable {

    private(set) var isCapturing = false

    // Mic writing via AVAudioFile (simpler than AVAssetWriter for mic-only)
    private var audioFile: AVAudioFile?
    private let writerQueue = DispatchQueue(label: "com.charlie.widget.audio-writer")

    // AVAssetWriter for system audio (ScreenCaptureKit gives CMSampleBuffer directly)
    private var assetWriter: AVAssetWriter?
    private var assetWriterInput: AVAssetWriterInput?

    // ScreenCaptureKit
    private var scStream: SCStream?
    private var streamOutput: AudioStreamOutput?

    // AVAudioEngine
    private var audioEngine: AVAudioEngine?

    // Format
    private let sampleRate: Double = 16000
    private let channels: AVAudioChannelCount = 1

    // MARK: - Start

    func start(source: AudioSource, outputURL: URL) async throws {
        guard !isCapturing else { throw RecorderError.alreadyRecording }

        if source == .systemAndMic {
            // System audio uses AVAssetWriter (receives CMSampleBuffer from SCStream)
            try setupAssetWriter(at: outputURL)
            try setupMicForMixing()
            try await setupSystemAudio()
        } else {
            // Mic-only uses AVAudioFile (simpler, more reliable)
            try setupMicOnly(outputURL: outputURL)
        }

        isCapturing = true
    }

    // MARK: - Stop

    func stop() async throws {
        guard isCapturing else { throw RecorderError.notRecording }

        // Stop capture sources
        if let stream = scStream {
            try? await stream.stopCapture()
            scStream = nil
            streamOutput = nil
        }

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

        // Finalize AVAudioFile (mic-only mode)
        audioFile = nil  // closing the file flushes it

        // Finalize AVAssetWriter (system+mic mode)
        if let writer = assetWriter, let input = assetWriterInput {
            assetWriter = nil
            assetWriterInput = nil
            try await finalizeWriter(writer, input: input)
        }

        isCapturing = false
    }

    private func finalizeWriter(_ writer: AVAssetWriter, input: AVAssetWriterInput) async throws {
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status == .failed {
            throw RecorderError.assetWriterFailed(
                writer.error?.localizedDescription ?? "unknown")
        }
    }

    // MARK: - Mic-Only Mode (AVAudioFile)

    private func setupMicOnly(outputURL: URL) throws {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let hwFormat = inputNode.outputFormat(forBus: 0)

        guard hwFormat.sampleRate > 0 else {
            throw RecorderError.permissionDenied("Microphone")
        }

        // Write as WAV (PCM) — reliable and simple
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: false
        )!

        let file = try AVAudioFile(
            forWriting: outputURL,
            settings: targetFormat.settings
        )
        audioFile = file

        let needsConversion = hwFormat.sampleRate != sampleRate || hwFormat.channelCount != channels
        let converter: AVAudioConverter? = needsConversion
            ? AVAudioConverter(from: hwFormat, to: targetFormat)
            : nil

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) {
            [weak self] buffer, _ in
            guard let self else { return }
            self.writerQueue.async {
                self.writeMicBuffer(buffer, converter: converter, targetFormat: targetFormat)
            }
        }

        try engine.start()
        audioEngine = engine
    }

    private func writeMicBuffer(
        _ buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter?,
        targetFormat: AVAudioFormat
    ) {
        guard let file = audioFile else { return }

        if let converter {
            let frameCapacity = AVAudioFrameCount(
                Double(buffer.frameLength) * (targetFormat.sampleRate / buffer.format.sampleRate)
            )
            guard frameCapacity > 0,
                  let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCapacity)
            else { return }

            var consumed = false
            var error: NSError?
            converter.convert(to: converted, error: &error) { _, outStatus in
                if consumed {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                consumed = true
                outStatus.pointee = .haveData
                return buffer
            }
            guard error == nil, converted.frameLength > 0 else { return }
            try? file.write(from: converted)
        } else {
            try? file.write(from: buffer)
        }
    }

    // MARK: - System+Mic Mode (AVAssetWriter)

    private func setupAssetWriter(at url: URL) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .m4a)

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: 64_000,
        ]

        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        writer.add(input)

        guard writer.startWriting() else {
            throw RecorderError.assetWriterFailed(
                writer.error?.localizedDescription ?? "startWriting failed")
        }
        writer.startSession(atSourceTime: .zero)

        assetWriter = writer
        assetWriterInput = input
    }

    private func setupMicForMixing() throws {
        // In system+mic mode, mic audio goes through AVAssetWriter too
        // For now, system audio captures both sides of Zoom already
        // Mic is optional enhancement — skip for Phase 1 system+mic
        // TODO: Phase 2 — mix mic PCM into the system audio stream
    }

    private func setupSystemAudio() async throws {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch {
            throw RecorderError.permissionDenied("Screen Recording")
        }

        guard let display = content.displays.first else {
            throw RecorderError.noDisplay
        }

        let filter = SCContentFilter(
            display: display,
            excludingApplications: [],
            exceptingWindows: []
        )

        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.sampleRate = Int(sampleRate)
        config.channelCount = Int(channels)
        // Minimal video (required on macOS 14)
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.showsCursor = false

        let output = AudioStreamOutput { [weak self] sampleBuffer in
            self?.appendSystemAudio(sampleBuffer)
        }

        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: .global(qos: .userInitiated))
        try await stream.startCapture()

        scStream = stream
        streamOutput = output
    }

    // MARK: - Append System Audio

    private func appendSystemAudio(_ sampleBuffer: CMSampleBuffer) {
        writerQueue.async { [weak self] in
            guard let self,
                  let input = self.assetWriterInput,
                  input.isReadyForMoreMediaData
            else { return }
            input.append(sampleBuffer)
        }
    }
}

// MARK: - SCStreamOutput Delegate

final class AudioStreamOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    private let onAudioSample: (CMSampleBuffer) -> Void

    init(onAudioSample: @escaping (CMSampleBuffer) -> Void) {
        self.onAudioSample = onAudioSample
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .audio else { return }
        onAudioSample(sampleBuffer)
    }
}
