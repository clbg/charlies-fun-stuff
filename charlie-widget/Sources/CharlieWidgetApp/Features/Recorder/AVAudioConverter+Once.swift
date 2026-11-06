@preconcurrency import AVFAudio

extension AVAudioConverter {
    /// Converts exactly one input buffer into `output`; returns the conversion error, if any.
    func convertOnce(_ input: AVAudioPCMBuffer, to output: AVAudioPCMBuffer) -> NSError? {
        // The input block may run on the converter's thread; a box keeps the one-shot flag Sendable-clean.
        final class Flag: @unchecked Sendable { var consumed = false }
        let flag = Flag()
        var error: NSError?
        convert(to: output, error: &error) { _, outStatus in
            if flag.consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            flag.consumed = true
            outStatus.pointee = .haveData
            return input
        }
        return error
    }
}
