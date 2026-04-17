@preconcurrency import AVFAudio
import AVFoundation
@preconcurrency import CoreMedia
@preconcurrency import ScreenCaptureKit

// MARK: - AudioCaptureManager

final class AudioCaptureManager: @unchecked Sendable {

    private(set) var isCapturing = false

    private let writerQueue = DispatchQueue(label: "com.charlie.widget.audio-writer")

    // AVAssetWriter — used for all modes (consistent .m4a output)
    private var assetWriter: AVAssetWriter?
    private var assetWriterInput: AVAssetWriterInput?       // system audio (or mic in mic-only)
    private var micWriterInput: AVAssetWriterInput?          // mic track in "both" mode
    private var sessionStarted = false

    // ScreenCaptureKit
    private var scStream: SCStream?
    private var streamOutput: AudioStreamOutput?

    // AVAudioEngine (mic capture)
    private var audioEngine: AVAudioEngine?

    // Format constants — use 48kHz for both modes (AAC encoder requires standard rates)
    static let outputSampleRate: Double = 48000
    private let channels: AVAudioChannelCount = 1

    // Audio level metering (0.0–1.0, updated from audio callbacks)
    var audioLevel: Float = 0
    var captureDeviceName: String = ""

    /// Optional callback to receive raw 16kHz mono Float32 audio samples for live transcription.
    /// Set before calling start(). Called from audio processing threads.
    /// Speaker label is "mic" or "system" (in both mode, each source forwards under its own label).
    var liveAudioCallback: (([Float], String) -> Void)?

    // Resampler for converting captured audio to 16kHz for WhisperKit
    private var whisperConverter: AVAudioConverter?
    private let whisperFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16000,
        channels: 1,
        interleaved: false
    )!

    // MARK: - Start

    func start(source: AudioSource, outputURL: URL) async throws {
        guard !isCapturing else { throw RecorderError.alreadyRecording }
        sessionStarted = false
        micSampleOffset = 0

        // For "both" mode, add mic input BEFORE startWriting
        let addMicTrack = (source == .both)
        try setupAssetWriter(at: outputURL, addMicTrack: addMicTrack)

        switch source {
        case .mic:
            try setupMic(writeTo: assetWriterInput!)
        case .system:
            try await setupSystemAudio()
        case .both:
            try setupMic(writeTo: micWriterInput!)
            try await setupSystemAudio()
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
        whisperConverter = nil

        // Finalize AVAssetWriter
        if let writer = assetWriter {
            let inputs = [assetWriterInput, micWriterInput].compactMap { $0 }
            assetWriter = nil
            assetWriterInput = nil
            micWriterInput = nil
            for input in inputs { input.markAsFinished() }
            await writer.finishWriting()
            if writer.status == .failed {
                throw RecorderError.assetWriterFailed(
                    writer.error?.localizedDescription ?? "unknown")
            }
        }

        isCapturing = false
    }

    // MARK: - Microphone Setup (shared by mic-only and both modes)

    private var micSampleOffset: Int64 = 0
    private var micTargetInput: AVAssetWriterInput?  // which writer input mic feeds into
    private var micConverter: AVAudioConverter?       // retained to survive release optimization
    private var micTargetFormat: AVAudioFormat?       // retained to survive release optimization

    private func setupMic(writeTo targetInput: AVAssetWriterInput) throws {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let hwFormat = inputNode.outputFormat(forBus: 0)

        guard hwFormat.sampleRate > 0 else {
            throw RecorderError.permissionDenied("Microphone")
        }

        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.outputSampleRate,
            channels: channels,
            interleaved: false
        )!

        let needsConversion = hwFormat.sampleRate != Self.outputSampleRate || hwFormat.channelCount != channels
        micConverter = needsConversion
            ? AVAudioConverter(from: hwFormat, to: targetFormat)
            : nil
        micTargetFormat = targetFormat
        micTargetInput = targetInput

        // Set up resampler for live transcription (48kHz -> 16kHz)
        whisperConverter = AVAudioConverter(from: targetFormat, to: whisperFormat)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) {
            [weak self] buffer, _ in
            guard let self, let targetFormat = self.micTargetFormat else { return }
            let converter = self.micConverter
            self.updateLevel(from: buffer)
            self.forwardToLiveTranscription(buffer, converter: converter, targetFormat: targetFormat, speaker: "mic")
            self.writerQueue.async {
                self.writeMicBuffer(buffer, converter: converter, targetFormat: targetFormat)
            }
        }

        // Set device name
        if let uid = inputNode.auAudioUnit.deviceID as? AudioDeviceID, uid != 0 {
            captureDeviceName = Self.deviceName(for: uid) ?? "Microphone"
        } else {
            captureDeviceName = "Default Microphone"
        }
        NSLog("[AudioCapture] mic tap installed, device=%@, hwFormat=%@", captureDeviceName, hwFormat.description)

        try engine.start()
        audioEngine = engine
    }

    private func writeMicBuffer(
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

        guard let cmBuffer = outputBuffer.toCMSampleBuffer(
            sampleRate: Self.outputSampleRate, sampleOffset: micSampleOffset
        ) else { return }

        if micSampleOffset == 0 {
            NSLog("[AudioCapture] first mic CMSampleBuffer, frames=\(outputBuffer.frameLength)")
        }
        micSampleOffset += Int64(outputBuffer.frameLength)

        // Write to the designated input (main input for mic-only, micWriterInput for both)
        guard let input = micTargetInput, input.isReadyForMoreMediaData else { return }
        if !sessionStarted, let writer = assetWriter {
            let pts = CMSampleBufferGetPresentationTimeStamp(cmBuffer)
            writer.startSession(atSourceTime: pts)
            sessionStarted = true
        }
        input.append(cmBuffer)
    }

    // MARK: - System Audio (ScreenCaptureKit)

    private func setupAssetWriter(at url: URL, addMicTrack: Bool = false) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .m4a)

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: Self.outputSampleRate,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: 64_000,
        ]

        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        writer.add(input)
        assetWriterInput = input

        // Add mic as second track BEFORE startWriting (AVAssetWriter requirement)
        if addMicTrack {
            let micInput = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
            micInput.expectsMediaDataInRealTime = true
            writer.add(micInput)
            micWriterInput = micInput
        }

        guard writer.startWriting() else {
            throw RecorderError.assetWriterFailed(
                writer.error?.localizedDescription ?? "startWriting failed")
        }

        // In "both" mode, start session at .zero immediately so both mic (PTS from 0)
        // and system audio (PTS from ScreenCaptureKit host time) are valid.
        // Single-source modes defer to first sample PTS.
        if addMicTrack {
            writer.startSession(atSourceTime: .zero)
            sessionStarted = true
        }

        assetWriter = writer
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
        config.sampleRate = Int(Self.outputSampleRate)
        config.channelCount = Int(channels)
        // Minimal video (required on macOS 14)
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.showsCursor = false

        captureDeviceName = "System Audio"

        let output = AudioStreamOutput { [weak self] sampleBuffer in
            self?.updateLevel(fromCM: sampleBuffer)
            self?.forwardSystemAudioToLiveTranscription(sampleBuffer)
            self?.appendSystemAudio(sampleBuffer)
        }

        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: .global(qos: .userInitiated))
        try await stream.startCapture()

        scStream = stream
        streamOutput = output
    }

    // MARK: - Live Transcription Forwarding

    /// Resample mic audio from hardware format to 16kHz and forward to live callback.
    private func forwardToLiveTranscription(
        _ buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter?,
        targetFormat: AVAudioFormat,
        speaker: String
    ) {
        guard let callback = liveAudioCallback else { return }

        // First, get audio in targetFormat (48kHz mono float32)
        let sourceBuffer: AVAudioPCMBuffer
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
            sourceBuffer = converted
        } else {
            sourceBuffer = buffer
        }

        // Now resample from 48kHz to 16kHz for WhisperKit
        guard let whisperConv = whisperConverter else { return }
        let ratio = 16000.0 / targetFormat.sampleRate
        let outFrames = AVAudioFrameCount(Double(sourceBuffer.frameLength) * ratio)
        guard outFrames > 0,
              let outBuffer = AVAudioPCMBuffer(pcmFormat: whisperFormat, frameCapacity: outFrames)
        else { return }

        var consumed = false
        var error: NSError?
        whisperConv.convert(to: outBuffer, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return sourceBuffer
        }
        guard error == nil, outBuffer.frameLength > 0,
              let floatData = outBuffer.floatChannelData?[0]
        else { return }

        let samples = Array(UnsafeBufferPointer(start: floatData, count: Int(outBuffer.frameLength)))
        callback(samples, speaker)
    }

    /// Forward system audio (CMSampleBuffer at 48kHz) to live transcription as 16kHz float samples.
    private func forwardSystemAudioToLiveTranscription(_ sampleBuffer: CMSampleBuffer) {
        guard let callback = liveAudioCallback else { return }
        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }

        let length = CMBlockBufferGetDataLength(dataBuffer)
        let sampleCount = length / MemoryLayout<Float>.size
        guard sampleCount > 0 else { return }

        // Read raw float32 samples (48kHz mono from ScreenCaptureKit)
        var rawSamples = [Float](repeating: 0, count: sampleCount)
        CMBlockBufferCopyDataBytes(dataBuffer, atOffset: 0, dataLength: length, destination: &rawSamples)

        // Create PCM buffer at 48kHz
        let srcFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.outputSampleRate,
            channels: 1,
            interleaved: false
        )!
        guard let srcBuffer = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: AVAudioFrameCount(sampleCount))
        else { return }
        srcBuffer.frameLength = AVAudioFrameCount(sampleCount)
        if let dst = srcBuffer.floatChannelData?[0] {
            rawSamples.withUnsafeBufferPointer { src in
                dst.initialize(from: src.baseAddress!, count: sampleCount)
            }
        }

        // Resample to 16kHz
        let ratio = 16000.0 / Self.outputSampleRate
        let outFrames = AVAudioFrameCount(Double(sampleCount) * ratio)
        guard outFrames > 0,
              let outBuffer = AVAudioPCMBuffer(pcmFormat: whisperFormat, frameCapacity: outFrames)
        else { return }

        let sysConverter = AVAudioConverter(from: srcFormat, to: whisperFormat)!
        var consumed = false
        var error: NSError?
        sysConverter.convert(to: outBuffer, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return srcBuffer
        }
        guard error == nil, outBuffer.frameLength > 0,
              let floatData = outBuffer.floatChannelData?[0]
        else { return }

        let samples = Array(UnsafeBufferPointer(start: floatData, count: Int(outBuffer.frameLength)))
        callback(samples, "system")
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

    // MARK: - Audio Level Metering

    private func updateLevel(from buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return }
        var sum: Float = 0
        for i in 0..<count { sum += data[i] * data[i] }
        let rms = sqrtf(sum / Float(count))
        audioLevel = min(rms * 5, 1.0)  // scale up for visibility, clamp to 1.0
    }

    private func updateLevel(fromCM sampleBuffer: CMSampleBuffer) {
        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        let length = CMBlockBufferGetDataLength(dataBuffer)
        let count = length / MemoryLayout<Float>.size
        guard count > 0 else { return }
        var data = [Float](repeating: 0, count: count)
        CMBlockBufferCopyDataBytes(dataBuffer, atOffset: 0, dataLength: length, destination: &data)
        var sum: Float = 0
        for s in data { sum += s * s }
        let rms = sqrtf(sum / Float(count))
        audioLevel = min(rms * 5, 1.0)
    }

    private static func deviceName(for deviceID: AudioDeviceID) -> String? {
        var name = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &name)
        return status == noErr ? name as String : nil
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
