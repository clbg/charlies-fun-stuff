@preconcurrency import AVFAudio
import AVFoundation
@preconcurrency import CoreMedia
@preconcurrency import ScreenCaptureKit

// MARK: - AudioCaptureManager

final class AudioCaptureManager: @unchecked Sendable {

    private(set) var isCapturing = false

    private let writerQueue = DispatchQueue(label: "com.charlie.widget.audio-writer")

    // AVAssetWriter — used for both modes (consistent .m4a output)
    private var assetWriter: AVAssetWriter?
    private var assetWriterInput: AVAssetWriterInput?
    private var sessionStarted = false

    // ScreenCaptureKit
    private var scStream: SCStream?
    private var streamOutput: AudioStreamOutput?

    // AVAudioEngine (mic capture)
    private var audioEngine: AVAudioEngine?

    // Format constants — use 48kHz for both modes (AAC encoder requires standard rates)
    private let outputSampleRate: Double = 48000
    private let channels: AVAudioChannelCount = 1

    // MARK: - Start

    func start(source: AudioSource, outputURL: URL) async throws {
        guard !isCapturing else { throw RecorderError.alreadyRecording }
        sessionStarted = false

        if source == .systemAndMic {
            // System audio via AVAssetWriter (receives CMSampleBuffer from SCStream)
            try setupAssetWriter(at: outputURL)
            try setupMicForMixing()
            try await setupSystemAudio()
        } else {
            // Mic-only also uses AVAssetWriter for consistent .m4a output
            try setupAssetWriter(at: outputURL)
            try setupMicOnly()
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

        // Finalize AVAssetWriter (used by both modes)
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

    // MARK: - Mic-Only Mode (AVAudioEngine → AVAssetWriter)

    /// Running sample count for generating CMSampleBuffer PTS from mic PCM buffers.
    private var micSampleOffset: Int64 = 0

    private func setupMicOnly() throws {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let hwFormat = inputNode.outputFormat(forBus: 0)

        guard hwFormat.sampleRate > 0 else {
            throw RecorderError.permissionDenied("Microphone")
        }

        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: outputSampleRate,
            channels: channels,
            interleaved: false
        )!

        let needsConversion = hwFormat.sampleRate != outputSampleRate || hwFormat.channelCount != channels
        let converter: AVAudioConverter? = needsConversion
            ? AVAudioConverter(from: hwFormat, to: targetFormat)
            : nil

        micSampleOffset = 0

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) {
            [weak self] buffer, _ in
            guard let self else { return }
            self.writerQueue.async {
                self.writeMicBufferToAssetWriter(
                    buffer, converter: converter, targetFormat: targetFormat)
            }
        }
        NSLog("[AudioCapture] mic tap installed, hwFormat=%@, needsConversion=%d", hwFormat.description, needsConversion ? 1 : 0)

        try engine.start()
        audioEngine = engine
    }

    private func writeMicBufferToAssetWriter(
        _ buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter?,
        targetFormat: AVAudioFormat
    ) {
        let outputBuffer: AVAudioPCMBuffer

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
            outputBuffer = converted
        } else {
            outputBuffer = buffer
        }

        // Convert AVAudioPCMBuffer to CMSampleBuffer for AVAssetWriter
        guard let cmBuffer = outputBuffer.toCMSampleBuffer(
            sampleRate: outputSampleRate, sampleOffset: micSampleOffset
        ) else {
            NSLog("[AudioCapture] toCMSampleBuffer returned nil, frames=\(outputBuffer.frameLength), channels=\(outputBuffer.format.channelCount), rate=\(outputBuffer.format.sampleRate)")
            return
        }

        if micSampleOffset == 0 {
            NSLog("[AudioCapture] first mic CMSampleBuffer created, frames=\(outputBuffer.frameLength)")
        }
        micSampleOffset += Int64(outputBuffer.frameLength)
        appendToAssetWriter(cmBuffer)
    }

    // MARK: - System+Mic Mode (AVAssetWriter)

    private func setupAssetWriter(at url: URL) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .m4a)

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: outputSampleRate,
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
        // NOTE: startSession is deferred to first sample (see appendToAssetWriter)
        // so PTS matches actual buffer timestamps, not .zero

        assetWriter = writer
        assetWriterInput = input
    }

    private func setupMicForMixing() throws {
        // Phase 1: mic mixing is intentionally skipped.
        //
        // ScreenCaptureKit captures all system audio, which already includes
        // your own voice in Zoom/Meet calls (the far-end mix contains your
        // mic audio as played through the speakers). For most meeting
        // recording use-cases this is sufficient.
        //
        // Phase 2 enhancement: install an AVAudioEngine tap on the mic,
        // convert PCM buffers to CMSampleBuffer, and interleave/mix them
        // into the AVAssetWriter alongside the system audio track.
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
        config.sampleRate = Int(outputSampleRate)
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

    // MARK: - Append Audio to AVAssetWriter

    private func appendSystemAudio(_ sampleBuffer: CMSampleBuffer) {
        writerQueue.async { [weak self] in
            self?.appendToAssetWriter(sampleBuffer)
        }
    }

    /// Shared method: appends a CMSampleBuffer to the AVAssetWriter.
    /// Defers `startSession(atSourceTime:)` to the first sample so the PTS
    /// matches the actual buffer timestamps (not .zero).
    private func appendToAssetWriter(_ sampleBuffer: CMSampleBuffer) {
        guard let writer = assetWriter,
              let input = assetWriterInput,
              input.isReadyForMoreMediaData
        else { return }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        if !sessionStarted {
            writer.startSession(atSourceTime: pts)
            sessionStarted = true
            NSLog("[AudioCapture] session started at PTS: \(pts.seconds)s")
        }

        if !input.append(sampleBuffer) {
            NSLog("[AudioCapture] append failed, writer status: \(writer.status.rawValue), error: \(writer.error?.localizedDescription ?? "none")")
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

// MARK: - AVAudioPCMBuffer → CMSampleBuffer

extension AVAudioPCMBuffer {
    /// Convert a PCM buffer into a CMSampleBuffer suitable for AVAssetWriterInput.
    func toCMSampleBuffer(sampleRate: Double, sampleOffset: Int64) -> CMSampleBuffer? {
        let frameCount = Int(frameLength)
        guard frameCount > 0, let floatData = floatChannelData?[0] else { return nil }

        // Interleaved Float32 mono — matches AVAssetWriterInput expectations for AAC encoding
        var asbd = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 32,
            mReserved: 0
        )

        var formatDescription: CMAudioFormatDescription?
        let status = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )
        guard status == noErr, let desc = formatDescription else { return nil }

        let pts = CMTime(value: sampleOffset, timescale: CMTimeScale(sampleRate))

        var sampleBuffer: CMSampleBuffer?
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(sampleRate)),
            presentationTimeStamp: pts,
            decodeTimeStamp: .invalid
        )

        let dataSize = frameCount * MemoryLayout<Float>.size

        var blockBuffer: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: dataSize,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: dataSize,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard let block = blockBuffer else { return nil }

        let replaceStatus = CMBlockBufferReplaceDataBytes(
            with: floatData,
            blockBuffer: block,
            offsetIntoDestination: 0,
            dataLength: dataSize
        )
        guard replaceStatus == kCMBlockBufferNoErr else { return nil }

        CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: block,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: desc,
            sampleCount: frameCount,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )

        return sampleBuffer
    }
}
