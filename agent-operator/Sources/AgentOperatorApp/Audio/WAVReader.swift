import AVFoundation

// MARK: - WAVReader

/// Reads a WAV file and returns its audio as 16 kHz mono Float32 samples.
///
/// Uses `AVAudioFile` and `AVAudioConverter` to handle format conversion
/// automatically, supporting any input sample rate, channel count, or
/// bit depth that Core Audio can decode.
enum WAVReader {

    // MARK: - Errors

    enum Error: Swift.Error, CustomStringConvertible {
        case fileNotFound(String)
        case failedToCreateOutputBuffer
        case conversionFailed(String)

        var description: String {
            switch self {
            case .fileNotFound(let path):
                return "WAV file not found: \(path)"
            case .failedToCreateOutputBuffer:
                return "Failed to create AVAudioPCMBuffer for output"
            case .conversionFailed(let detail):
                return "Audio conversion failed: \(detail)"
            }
        }
    }

    // MARK: - Constants

    /// Target sample rate that SpeechRecognizer expects.
    private static let targetSampleRate: Double = 16_000

    // MARK: - Public API

    /// Read a WAV (or any Core Audio-supported) file and return 16 kHz
    /// mono Float32 samples suitable for WhisperKit.
    ///
    /// - Parameter path: Absolute path to the audio file.
    /// - Returns: Array of Float32 samples at 16 kHz.
    static func readFloat32(from path: String) throws -> [Float] {
        let url = URL(fileURLWithPath: path)

        guard FileManager.default.fileExists(atPath: path) else {
            throw Error.fileNotFound(path)
        }

        let sourceFile = try AVAudioFile(forReading: url)
        let sourceFormat = sourceFile.processingFormat
        let sourceFrameCount = AVAudioFrameCount(sourceFile.length)

        // Build target format: 16 kHz, mono, Float32, non-interleaved.
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw Error.conversionFailed("Could not create target AVAudioFormat")
        }

        // If the source already matches, just read directly.
        if sourceFormat.sampleRate == targetSampleRate
            && sourceFormat.channelCount == 1
            && sourceFormat.commonFormat == .pcmFormatFloat32 {
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: sourceFormat,
                frameCapacity: sourceFrameCount
            ) else {
                throw Error.failedToCreateOutputBuffer
            }
            try sourceFile.read(into: buffer)
            return Array(UnsafeBufferPointer(
                start: buffer.floatChannelData![0],
                count: Int(buffer.frameLength)
            ))
        }

        // Read the source file into a buffer in its native format.
        guard let sourceBuffer = AVAudioPCMBuffer(
            pcmFormat: sourceFormat,
            frameCapacity: sourceFrameCount
        ) else {
            throw Error.failedToCreateOutputBuffer
        }
        try sourceFile.read(into: sourceBuffer)

        // Create converter.
        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw Error.conversionFailed("Could not create AVAudioConverter")
        }

        // Calculate output frame count based on sample rate ratio.
        let ratio = targetSampleRate / sourceFormat.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(sourceFrameCount) * ratio)

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: outputFrameCount
        ) else {
            throw Error.failedToCreateOutputBuffer
        }

        // Convert.
        var convError: NSError?
        var inputConsumed = false
        let status = converter.convert(to: outputBuffer, error: &convError) { _, outStatus in
            if inputConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            outStatus.pointee = .haveData
            inputConsumed = true
            return sourceBuffer
        }

        if let convError {
            throw Error.conversionFailed(convError.localizedDescription)
        }
        if status == .error {
            throw Error.conversionFailed("AVAudioConverter returned error status")
        }

        let count = Int(outputBuffer.frameLength)
        guard count > 0, let channelData = outputBuffer.floatChannelData else {
            return []
        }

        return Array(UnsafeBufferPointer(start: channelData[0], count: count))
    }
}
