import Foundation

// MARK: - Bedrock (InvokeModelWithResponseStream, SigV4, AWS event stream)

struct BedrockProvider: LLMProvider {
    let config: LLMConfig

    func stream(_ request: LLMRequest) -> AsyncThrowingStream<LLMEvent, Error> {
        let config = self.config
        return LLMStreamRunner.run(label: "bedrock \(config.model)") { emit in
            try await Self.send(request, config: config, emit: emit, allowRetry: true)
        }
    }

    func warmUp() async {
        do {
            for try await _ in stream(.warmUp) {}
        } catch {
            LLMDebug.log("bedrock warmUp failed: \(error.localizedDescription)")
        }
    }

    /// `/model/{percent-encoded id}/invoke-with-response-stream` — `:` in ids becomes `%3A`.
    static func encodedPath(model: String) -> String {
        "/model/\(SigV4.uriEncode(model))/invoke-with-response-stream"
    }

    static func makeRequest(_ request: LLMRequest, config: LLMConfig, credentials: AWSCredentials) throws -> URLRequest {
        guard !config.model.isEmpty else { throw LLMError.invalidConfig("Bedrock model id is empty") }
        let region = config.awsRegion.isEmpty ? "us-west-2" : config.awsRegion
        let host = "bedrock-runtime.\(region).amazonaws.com"
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = host
        comps.percentEncodedPath = encodedPath(model: config.model)
        guard let url = comps.url else { throw LLMError.invalidConfig("bad Bedrock URL for model \(config.model)") }

        var body = AnthropicBody.make(request, config: config)
        body["anthropic_version"] = "bedrock-2023-05-31"
        let data = try JSONSerialization.data(withJSONObject: body)

        let baseHeaders = ["content-type": "application/json", "accept": "application/vnd.amazon.eventstream"]
        let signed = SigV4.sign(method: "POST", host: host, encodedPath: comps.percentEncodedPath, query: nil,
                                headers: baseHeaders, body: data, region: region, service: "bedrock",
                                credentials: credentials)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = data
        for (k, v) in baseHeaders.merging(signed, uniquingKeysWith: { $1 }) { req.setValue(v, forHTTPHeaderField: k) }
        return req
    }

    static func send(_ request: LLMRequest, config: LLMConfig, emit: @Sendable (String) -> Void, allowRetry: Bool) async throws {
        let creds = try await AWSCredentialStore.shared.credentials(profile: config.awsProfile)
        try Task.checkCancellation()
        let req = try makeRequest(request, config: config, credentials: creds)
        let bytes: URLSession.AsyncBytes
        do {
            bytes = try await LLMHTTP.open(req)
        } catch LLMError.http(let status, let message)
            where allowRetry && (status == 403 || status == 400) && Self.looksLikeCredentialError(message) {
            // Cached creds were revoked/expired early (e.g. after mwinit): refetch once.
            LLMDebug.log("bedrock: credential error (\(status)), refetching credentials")
            await AWSCredentialStore.shared.invalidate(profile: config.awsProfile)
            return try await send(request, config: config, emit: emit, allowRetry: false)
        }
        var decoder = EventStreamDecoder()
        for try await b in bytes {
            guard let msg = try decoder.feed(b) else { continue }
            switch try BedrockStreamParser.interpret(msg) {
            case .text(let t): emit(t)
            case .stop: return
            case .ignore: break
            }
        }
    }

    static func looksLikeCredentialError(_ m: String) -> Bool {
        let l = m.lowercased()
        return l.contains("security token") || l.contains("expired") || l.contains("signature")
    }
}

// MARK: - Anthropic Messages API (SSE)

struct AnthropicProvider: LLMProvider {
    let config: LLMConfig
    static let apiVersion = "2026-10-21"

    func stream(_ request: LLMRequest) -> AsyncThrowingStream<LLMEvent, Error> {
        let config = self.config
        return LLMStreamRunner.run(label: "anthropic \(config.model)") { emit in
            let req = try Self.makeRequest(request, config: config, apiKey: LLMKeychain.resolvedKey(for: .anthropic))
            let bytes = try await LLMHTTP.open(req)
            var sse = SSEParser()
            for try await b in bytes {
                guard let ev = sse.feed(b) else { continue }
                switch try AnthropicStreamParser.interpret(sse: ev) {
                case .text(let t): emit(t)
                case .stop: return
                case .ignore: break
                }
            }
            if let ev = sse.finish(), case .text(let t) = try AnthropicStreamParser.interpret(sse: ev) { emit(t) }
        }
    }

    func warmUp() async {
        guard LLMKeychain.resolvedKeyOrNil(for: .anthropic) != nil else { return }
        do { for try await _ in stream(.warmUp) {} } catch {
            LLMDebug.log("anthropic warmUp failed: \(error.localizedDescription)")
        }
    }

    static func makeRequest(_ request: LLMRequest, config: LLMConfig, apiKey: String) throws -> URLRequest {
        let base = config.baseURL.isEmpty ? "https://api.anthropic.com" : config.baseURL
        guard let url = URL(string: base.trimmingSuffix("/") + "/v1/messages") else {
            throw LLMError.invalidConfig("bad Anthropic base URL")
        }
        guard !config.model.isEmpty else { throw LLMError.invalidConfig("Anthropic model is empty") }
        var body = AnthropicBody.make(request, config: config)
        body["model"] = config.model
        body["stream"] = true
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue("text/event-stream", forHTTPHeaderField: "accept")
        return req
    }
}

// MARK: - OpenAI-compatible chat.completions (SSE)

struct OpenAICompatibleProvider: LLMProvider {
    let config: LLMConfig

    func stream(_ request: LLMRequest) -> AsyncThrowingStream<LLMEvent, Error> {
        let config = self.config
        return LLMStreamRunner.run(label: "openai \(config.model)") { emit in
            let req = try Self.makeRequest(request, config: config, apiKey: LLMKeychain.resolvedKeyOrNil(for: config.kind))
            let bytes = try await LLMHTTP.open(req)
            var sse = SSEParser()
            for try await b in bytes {
                guard let ev = sse.feed(b) else { continue }
                switch try OpenAIStreamParser.interpret(data: ev.data) {
                case .text(let t): emit(t)
                case .stop: return
                case .ignore: break
                }
            }
            if let ev = sse.finish(), case .text(let t) = try OpenAIStreamParser.interpret(data: ev.data) { emit(t) }
        }
    }

    func warmUp() async {
        guard !Self.baseURL(config).isEmpty, !config.model.isEmpty else { return }
        do { for try await _ in stream(.warmUp) {} } catch {
            LLMDebug.log("openai warmUp failed: \(error.localizedDescription)")
        }
    }

    static func baseURL(_ config: LLMConfig) -> String {
        config.baseURL.isEmpty ? config.kind.defaultBaseURL : config.baseURL
    }

    /// Provider-specific knobs to keep first-token latency low:
    /// - DeepSeek: thinking is on by default → `thinking: {"type": "disabled"}` (config.thinking).
    /// - Gemini / generic: `reasoning_effort` (config.effort); Gemini 3 can't disable thinking, "minimal" is lowest.
    static func extras(_ config: LLMConfig) -> [String: Any] {
        var x: [String: Any] = [:]
        if config.kind == .deepseek, let t = config.thinking { x["thinking"] = ["type": t] }
        if config.kind != .deepseek, let e = config.effort { x["reasoning_effort"] = e }
        return x
    }

    static func body(_ request: LLMRequest, model: String) -> [String: Any] {
        var messages: [[String: Any]] = []
        if !request.system.isEmpty { messages.append(["role": "system", "content": request.system]) }
        for m in request.messages {
            let parts: [[String: Any]] = m.content.map {
                switch $0 {
                case .text(let s): return ["type": "text", "text": s]
                case .imagePNG(let d):
                    return ["type": "image_url", "image_url": ["url": "data:image/png;base64,\(d.base64EncodedString())"]]
                }
            }
            // Plain string content for text-only messages: widest compatibility across "OpenAI-compatible" servers.
            if m.content.count == 1, case .text(let s) = m.content[0] {
                messages.append(["role": m.role, "content": s])
            } else {
                messages.append(["role": m.role, "content": parts])
            }
        }
        return ["model": model, "messages": messages, "max_tokens": request.maxTokens, "stream": true]
    }

    static func makeRequest(_ request: LLMRequest, config: LLMConfig, apiKey: String?) throws -> URLRequest {
        let base = baseURL(config)
        guard !base.isEmpty, let url = URL(string: base.trimmingSuffix("/") + "/chat/completions") else {
            throw LLMError.invalidConfig("\(config.kind.displayName) base URL is empty or invalid")
        }
        guard !config.model.isEmpty else { throw LLMError.invalidConfig("\(config.kind.displayName) model is empty") }
        if config.kind != .openAICompatible, apiKey?.isEmpty ?? true { throw LLMError.missingAPIKey(config.kind) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = try JSONSerialization.data(
            withJSONObject: body(request, model: config.model).merging(extras(config)) { a, _ in a })
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue("text/event-stream", forHTTPHeaderField: "accept")
        if let apiKey, !apiKey.isEmpty { req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "authorization") }
        return req
    }
}

extension String {
    func trimmingSuffix(_ s: String) -> String {
        var r = self
        while r.hasSuffix(s) { r.removeLast(s.count) }
        return r
    }
}
