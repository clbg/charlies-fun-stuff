import Foundation

/// Offline checks for the parsers / signer / request builders (run via `llm-smoke --selftest`).
public enum LLMSelfTest {
    public struct Check: Sendable { public let name: String; public let ok: Bool; public let detail: String }

    public static func run() -> [Check] {
        var checks: [Check] = []
        func check(_ name: String, _ body: () throws -> (Bool, String)) {
            do {
                let (ok, detail) = try body()
                checks.append(Check(name: name, ok: ok, detail: detail))
            } catch {
                checks.append(Check(name: name, ok: false, detail: "threw \(error)"))
            }
        }
        func expectThrows(_ name: String, _ body: () throws -> Void) {
            do { try body(); checks.append(Check(name: name, ok: false, detail: "did not throw")) }
            catch { checks.append(Check(name: name, ok: true, detail: "threw: \(error.localizedDescription)")) }
        }

        // --- Anthropic SSE ---
        let anthropicSSE = """
        event: message_start\r
        data: {"type":"message_start","message":{"id":"msg_1","role":"assistant","content":[]}}\r
        \r
        event: content_block_start\r
        data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}\r
        \r
        : keepalive comment\r
        event: ping\r
        data: {"type": "ping"}\r
        \r
        event: content_block_delta\r
        data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"hmm"}}\r
        \r
        event: content_block_delta\r
        data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"こんにちは"}}\r
        \r
        event: content_block_delta\r
        data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"、世界"}}\r
        \r
        event: message_delta\r
        data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}\r
        \r
        event: message_stop\r
        data: {"type":"message_stop"}\r
        \r

        """
        check("anthropic SSE: text deltas + stop (CRLF, comments, ping, thinking ignored)") {
            let events = SSEParser.parse(anthropicSSE)
            var texts: [String] = []
            var stopped = false
            for e in events {
                switch try AnthropicStreamParser.interpret(sse: e) {
                case .text(let t): texts.append(t)
                case .stop: stopped = true
                case .ignore: break
                }
            }
            return (events.count == 8 && texts == ["こんにちは", "、世界"] && stopped,
                    "events=\(events.count) texts=\(texts) stop=\(stopped)")
        }
        check("SSE: UTF-8 split across byte feeds + multi-line data + no trailing blank line") {
            var p = SSEParser()
            var out: [SSEEvent] = []
            for b in Array("event: x\ndata: 日本\ndata: 語".utf8) { if let e = p.feed(b) { out.append(e) } }
            if let e = p.finish() { out.append(e) }
            return (out == [SSEEvent(event: "x", data: "日本\n語")], "\(out)")
        }
        expectThrows("anthropic SSE: error event throws") {
            let ev = SSEParser.parse("event: error\ndata: {\"type\":\"error\",\"error\":{\"type\":\"overloaded_error\",\"message\":\"Overloaded\"}}\n\n")
            _ = try AnthropicStreamParser.interpret(sse: ev[0])
        }

        // --- OpenAI SSE ---
        let openAISSE = """
        data: {"id":"c1","choices":[{"index":0,"delta":{"role":"assistant","content":""}}]}

        data: {"id":"c1","choices":[{"index":0,"delta":{"content":"字幕"}}]}

        data: {"id":"c1","choices":[{"index":0,"delta":{"reasoning_content":"think"}}]}

        data: {"id":"c1","choices":[{"index":0,"delta":{"content":"の説明"},"finish_reason":null}]}

        data: {"id":"c1","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}

        data: [DONE]


        """
        check("openai SSE: content deltas, role/reasoning chunks ignored, [DONE] stops") {
            var texts: [String] = []
            var stopped = false
            for e in SSEParser.parse(openAISSE) {
                switch try OpenAIStreamParser.interpret(data: e.data) {
                case .text(let t): texts.append(t)
                case .stop: stopped = true
                case .ignore: break
                }
            }
            return (texts == ["字幕", "の説明"] && stopped, "texts=\(texts) stop=\(stopped)")
        }
        expectThrows("openai SSE: error object throws") {
            _ = try OpenAIStreamParser.interpret(data: "{\"error\":{\"message\":\"Invalid API key\",\"type\":\"auth\"}}")
        }

        // --- AWS event stream ---
        func chunk(_ inner: String) -> [UInt8] {
            let payload = try! JSONSerialization.data(withJSONObject: ["bytes": Data(inner.utf8).base64EncodedString(), "p": "abc"])
            return EventStreamDecoder.encode(headers: [(":event-type", "chunk"), (":content-type", "application/json"), (":message-type", "event")],
                                             payload: payload)
        }
        check("event-stream: two chunk frames fed byte-by-byte decode to text + stop") {
            let frames = chunk(#"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"東京"}}"#)
                + chunk(#"{"type":"message_stop","amazon-bedrock-invocationMetrics":{"inputTokenCount":3}}"#)
            var d = EventStreamDecoder()
            let msgs = try d.feed(frames)
            let actions = try msgs.map(BedrockStreamParser.interpret)
            return (actions == [.text("東京"), .stop], "\(actions)")
        }
        expectThrows("event-stream: exception frame throws with message") {
            let f = EventStreamDecoder.encode(headers: [(":exception-type", "throttlingException"), (":message-type", "exception")],
                                              payload: Data(#"{"message":"Too many requests"}"#.utf8))
            var d = EventStreamDecoder()
            for m in try d.feed(f) { _ = try BedrockStreamParser.interpret(m) }
        }
        expectThrows("event-stream: corrupted message CRC throws") {
            var f = chunk(#"{"type":"ping"}"#)
            f[f.count - 6] ^= 0xFF
            var d = EventStreamDecoder()
            _ = try d.feed(f)
        }

        // --- SigV4 ---
        check("sigv4: AWS docs IAM ListUsers test vector") {
            let creds = AWSCredentials(accessKeyId: "AKIDEXAMPLE", secretAccessKey: "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY",
                                       sessionToken: nil, expiration: nil)
            var c = DateComponents(); c.year = 2015; c.month = 8; c.day = 30; c.hour = 12; c.minute = 36; c.second = 0
            var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
            let h = SigV4.sign(method: "GET", host: "iam.amazonaws.com", encodedPath: "/",
                               query: "Version=2010-05-08&Action=ListUsers",
                               headers: ["Content-Type": "application/x-www-form-urlencoded; charset=utf-8"],
                               body: Data(), region: "us-east-1", service: "iam", credentials: creds, date: cal.date(from: c)!)
            let auth = h["authorization"] ?? ""
            let want = "Signature=5d672d79c15b13162d9279b0855cfba6789a8edb4c82c400e06b5924a6f2b5d7"
            return (auth.hasSuffix(want) && auth.contains("SignedHeaders=content-type;host;x-amz-date"), "signature matches=\(auth.hasSuffix(want))")
        }
        check("bedrock: ':' in model id → %3A in URL path, %253A in canonical URI") {
            let p = BedrockProvider.encodedPath(model: "jp.anthropic.claude-haiku-4-5-20251001-v1:0")
            let canon = SigV4.canonicalURI(encodedPath: p)
            return (p == "/model/jp.anthropic.claude-haiku-4-5-20251001-v1%3A0/invoke-with-response-stream"
                    && canon == "/model/jp.anthropic.claude-haiku-4-5-20251001-v1%253A0/invoke-with-response-stream",
                    "path=\(p) canonical=\(canon)")
        }
        check("bedrock: URLRequest keeps %3A, signs host/x-amz-date/token, body has anthropic_version & no model/stream") {
            let creds = AWSCredentials(accessKeyId: "AKIDEXAMPLE", secretAccessKey: "secret", sessionToken: "tok", expiration: nil)
            var cfg = LLMPresets.preset(id: "bedrock-jp-haiku-4-5")!.config
            let req = try BedrockProvider.makeRequest(sampleRequest, config: cfg, credentials: creds)
            let body = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
            let auth = req.value(forHTTPHeaderField: "authorization") ?? ""
            let okURL = req.url!.absoluteString == "https://bedrock-runtime.ap-northeast-1.amazonaws.com/model/jp.anthropic.claude-haiku-4-5-20251001-v1%3A0/invoke-with-response-stream"
            let okBody = body["anthropic_version"] as? String == "bedrock-2023-05-31" && body["model"] == nil && body["stream"] == nil
                && body["thinking"] == nil && body["output_config"] == nil
            cfg = LLMConfig.default
            let req2 = try BedrockProvider.makeRequest(sampleRequest, config: cfg, credentials: creds)
            let body2 = try JSONSerialization.jsonObject(with: req2.httpBody!) as! [String: Any]
            let okBody2 = (body2["thinking"] as? [String: String]) == ["type": "between_tools"]
                && (body2["output_config"] as? [String: String]) == ["effort": "low"]
            let okAuth = auth.contains("SignedHeaders=accept;content-type;host;x-amz-date;x-amz-security-token")
            return (okURL && okBody && okBody2 && okAuth, "url=\(okURL) body=\(okBody) body(default)=\(okBody2) signedHeaders=\(okAuth)")
        }
        check("bedrock: image block is base64 PNG source") {
            let blk = AnthropicBody.block(.imagePNG(Data([0x89, 0x50])))
            let src = blk["source"] as? [String: String]
            return (blk["type"] as? String == "image" && src == ["type": "base64", "media_type": "image/png", "data": "iVA="], "\(blk)")
        }

        // --- Anthropic / OpenAI request builders ---
        check("anthropic: URL, headers, body has model + stream:true") {
            let cfg = LLMPresets.preset(id: "anthropic-sonnet-5-5")!.config
            let req = try AnthropicProvider.makeRequest(sampleRequest, config: cfg, apiKey: "test-key")
            let body = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
            let ok = req.url!.absoluteString == "https://api.anthropic.com/v1/messages"
                && req.value(forHTTPHeaderField: "x-api-key") == "test-key"
                && req.value(forHTTPHeaderField: "anthropic-version") == "2026-10-21"
                && body["model"] as? String == "claude-sonnet-5-5" && body["stream"] as? Bool == true
                && body["system"] as? String == "sys"
            return (ok, "url=\(req.url!.absoluteString)")
        }
        check("openai: URL, bearer, system message, image_url data URL") {
            let cfg = LLMConfig(kind: .openAICompatible, model: "deepseek-chat", baseURL: "https://api.deepseek.com/v1/")
            var r = sampleRequest
            r.messages = [LLMMessage(role: "user", content: [.text("見て"), .imagePNG(Data([1, 2, 3]))])]
            let req = try OpenAICompatibleProvider.makeRequest(r, config: cfg, apiKey: "k")
            let body = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
            let msgs = body["messages"] as! [[String: Any]]
            let parts = msgs[1]["content"] as! [[String: Any]]
            let url = (parts[1]["image_url"] as? [String: String])?["url"]
            let ok = req.url!.absoluteString == "https://api.deepseek.com/v1/chat/completions"
                && req.value(forHTTPHeaderField: "authorization") == "Bearer k"
                && msgs[0]["role"] as? String == "system" && body["stream"] as? Bool == true
                && parts[1]["type"] as? String == "image_url" && url == "data:image/png;base64,AQID"
            return (ok, "url=\(req.url!.absoluteString) image=\(url ?? "nil")")
        }
        check("config: tolerant Codable round trip") {
            let data = try JSONEncoder().encode(LLMConfig.default)
            let back = try JSONDecoder().decode(LLMConfig.self, from: data)
            let partial = try JSONDecoder().decode(LLMConfig.self, from: Data(#"{"kind":"anthropic","model":"claude-haiku-4-5"}"#.utf8))
            return (back == .default && partial.kind == .anthropic && partial.awsProfile == "claude-code", "ok")
        }
        check("benchmark: median") {
            let a = LLMBenchmark.Result(ttftMs: [900, 700, 800], error: nil).medianTTFTMs
            let b = LLMBenchmark.Result(ttftMs: [1, 2, 3, 4], error: nil).medianTTFTMs
            return (a == 800 && b == 2 && LLMBenchmark.Result(ttftMs: [], error: nil).medianTTFTMs == nil, "\(String(describing: a)) \(String(describing: b))")
        }
        return checks
    }

    static let sampleRequest = LLMRequest(system: "sys", messages: [LLMMessage(role: "user", content: [.text("hi")])], maxTokens: 16)
}
