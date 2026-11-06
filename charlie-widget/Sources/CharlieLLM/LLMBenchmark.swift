import Foundation

public enum LLMBenchmark {
    public struct Result: Sendable {
        /// One TTFT sample per successful prompt, in order.
        public let ttftMs: [Int]
        /// First error encountered (other prompts still run), or nil.
        public let error: String?

        public init(ttftMs: [Int], error: String?) {
            self.ttftMs = ttftMs
            self.error = error
        }

        public var medianTTFTMs: Int? {
            guard !ttftMs.isEmpty else { return nil }
            let s = ttftMs.sorted()
            return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
        }
    }

    /// Warms up (credentials + TLS), then runs each prompt sequentially and records time-to-first-token.
    public static func measure(_ config: LLMConfig, system: String, prompts: [String], maxTokens: Int) async -> Result {
        let provider = LLM.provider(for: config)
        await provider.warmUp()
        var samples: [Int] = []
        var firstError: String?
        for prompt in prompts {
            if Task.isCancelled { break }
            let req = LLMRequest(system: system, messages: [LLMMessage(role: "user", content: [.text(prompt)])],
                                 maxTokens: maxTokens)
            do {
                for try await ev in provider.stream(req) {
                    if case .done(let ttft, _) = ev { samples.append(ttft) }
                }
            } catch {
                if firstError == nil { firstError = error.localizedDescription }
            }
        }
        return Result(ttftMs: samples, error: firstError)
    }
}
