import Foundation

/// One process-wide URLSession so every provider reuses warm HTTP/2 + TLS connections.
enum LLMHTTP {
    static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.urlCache = nil
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.httpCookieStorage = nil
        cfg.httpShouldSetCookies = false
        cfg.waitsForConnectivity = false
        cfg.timeoutIntervalForRequest = 60      // idle timeout between bytes
        cfg.timeoutIntervalForResource = 300
        cfg.httpMaximumConnectionsPerHost = 6
        cfg.networkServiceType = .responsiveData
        return URLSession(configuration: cfg)
    }()

    /// Sends the request and returns the streaming body. Non-2xx responses are drained and thrown as `LLMError.http`.
    static func open(_ request: URLRequest) async throws -> URLSession.AsyncBytes {
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.stream("non-HTTP response")
        }
        if !(200..<300).contains(http.statusCode) {
            var body = Data()
            for try await b in bytes {
                body.append(b)
                if body.count > 64 * 1024 { break }
            }
            throw LLMError.http(status: http.statusCode, message: errorMessage(from: body))
        }
        return bytes
    }

    /// Pulls a human-readable message out of common JSON error shapes; falls back to the raw body.
    static func errorMessage(from body: Data) -> String {
        if let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            if let m = obj["message"] as? String { return m }
            if let m = obj["Message"] as? String { return m }
            if let e = obj["error"] as? [String: Any] {
                let type = e["type"] as? String
                let msg = e["message"] as? String ?? ""
                return type.map { "\($0): \(msg)" } ?? msg
            }
            if let e = obj["error"] as? String { return e }
        }
        let s = String(decoding: body.prefix(2000), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? "(empty body)" : s
    }
}

/// Wraps a provider's streaming body into an `AsyncThrowingStream<LLMEvent>` with timing and cancellation.
enum LLMStreamRunner {
    final class Timer: @unchecked Sendable {   // only touched from the single producer task
        let start = DispatchTime.now().uptimeNanoseconds
        var firstText: UInt64?
        func ms(_ t: UInt64) -> Int { Int((t - start) / 1_000_000) }
    }

    static func run(
        label: String,
        _ body: @escaping @Sendable (_ emit: @escaping @Sendable (String) -> Void) async throws -> Void
    ) -> AsyncThrowingStream<LLMEvent, Error> {
        AsyncThrowingStream { continuation in
            let timer = Timer()
            let task = Task {
                do {
                    try await body { text in
                        guard !text.isEmpty else { return }
                        if timer.firstText == nil { timer.firstText = DispatchTime.now().uptimeNanoseconds }
                        continuation.yield(.text(text))
                    }
                    let end = DispatchTime.now().uptimeNanoseconds
                    let total = timer.ms(end)
                    let ttft = timer.firstText.map { timer.ms($0) } ?? total
                    continuation.yield(.done(ttftMs: ttft, totalMs: total))
                    continuation.finish()
                } catch {
                    if Task.isCancelled || (error as? URLError)?.code == .cancelled || error is CancellationError {
                        LLMDebug.log("\(label): request cancelled after \(timer.ms(DispatchTime.now().uptimeNanoseconds)) ms")
                        continuation.finish(throwing: CancellationError())
                    } else {
                        LLMDebug.log("\(label): error \(error.localizedDescription)")
                        continuation.finish(throwing: error)
                    }
                }
            }
            continuation.onTermination = { reason in
                if case .cancelled = reason { task.cancel() }
            }
        }
    }
}

/// Builds the Anthropic Messages content blocks shared by Bedrock and the Anthropic API.
enum AnthropicBody {
    static func make(_ request: LLMRequest, config: LLMConfig) -> [String: Any] {
        var body: [String: Any] = [
            "max_tokens": request.maxTokens,
            "messages": request.messages.map { msg -> [String: Any] in
                ["role": msg.role, "content": msg.content.map(block)]
            },
        ]
        if !request.system.isEmpty { body["system"] = request.system }
        if let t = config.thinking, !t.isEmpty { body["thinking"] = ["type": t] }
        if let e = config.effort, !e.isEmpty { body["output_config"] = ["effort": e] }
        return body
    }

    static func block(_ c: LLMContent) -> [String: Any] {
        switch c {
        case .text(let s):
            return ["type": "text", "text": s]
        case .imagePNG(let data):
            return ["type": "image",
                    "source": ["type": "base64", "media_type": "image/png", "data": data.base64EncodedString()]]
        }
    }
}

extension LLMRequest {
    /// Tiny request used by `warmUp()` to open the connection.
    static let warmUp = LLMRequest(system: "", messages: [LLMMessage(role: "user", content: [.text("hi")])], maxTokens: 1)
}
