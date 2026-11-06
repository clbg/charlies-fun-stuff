import Foundation

// Pure, network-free parsers. Exercised by `llm-smoke --selftest`.

// MARK: - Server-Sent Events

public struct SSEEvent: Sendable, Equatable {
    public var event: String?
    public var data: String
}

/// Incremental byte-level SSE parser (handles \n and \r\n, multi-line `data:`, comments, UTF-8 split across chunks).
public struct SSEParser: Sendable {
    private var line: [UInt8] = []
    private var eventName: String?
    private var dataLines: [String] = []

    public init() {}

    /// Feed one byte; returns an event when a blank line completes one.
    public mutating func feed(_ byte: UInt8) -> SSEEvent? {
        if byte != UInt8(ascii: "\n") {
            line.append(byte)
            return nil
        }
        if line.last == UInt8(ascii: "\r") { line.removeLast() }
        let text = String(decoding: line, as: UTF8.self)
        line.removeAll(keepingCapacity: true)
        return processLine(text)
    }

    /// Flush a trailing event if the stream ended without a final blank line.
    public mutating func finish() -> SSEEvent? {
        if !line.isEmpty {
            if line.last == UInt8(ascii: "\r") { line.removeLast() }
            let text = String(decoding: line, as: UTF8.self)
            line.removeAll()
            if let ev = processLine(text) { return ev }
        }
        return dispatch()
    }

    private mutating func processLine(_ text: String) -> SSEEvent? {
        if text.isEmpty { return dispatch() }
        if text.hasPrefix(":") { return nil }  // comment
        let field: Substring
        var value: Substring
        if let colon = text.firstIndex(of: ":") {
            field = text[..<colon]
            value = text[text.index(after: colon)...]
            if value.first == " " { value = value.dropFirst() }
        } else {
            field = Substring(text)
            value = ""
        }
        switch field {
        case "event": eventName = String(value)
        case "data": dataLines.append(String(value))
        default: break  // id, retry
        }
        return nil
    }

    private mutating func dispatch() -> SSEEvent? {
        defer { eventName = nil; dataLines.removeAll() }
        guard !dataLines.isEmpty else { return nil }
        return SSEEvent(event: eventName, data: dataLines.joined(separator: "\n"))
    }

    /// Convenience for tests: parse a whole SSE document.
    public static func parse(_ text: String) -> [SSEEvent] {
        var p = SSEParser()
        var out: [SSEEvent] = []
        for b in text.utf8 { if let e = p.feed(b) { out.append(e) } }
        if let e = p.finish() { out.append(e) }
        return out
    }
}

/// What a single provider stream event means for the caller.
public enum StreamAction: Sendable, Equatable {
    case text(String)
    case stop
    case ignore
}

// MARK: - Anthropic Messages stream events (used by Anthropic API SSE and Bedrock chunks)

public enum AnthropicStreamParser {
    /// Interprets one Anthropic stream event JSON object. Throws on `{"type":"error"}`.
    public static func interpret(json data: Data) throws -> StreamAction {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMError.stream("malformed event JSON: \(String(decoding: data.prefix(200), as: UTF8.self))")
        }
        switch obj["type"] as? String {
        case "content_block_delta":
            if let delta = obj["delta"] as? [String: Any],
               delta["type"] as? String == "text_delta",
               let text = delta["text"] as? String {
                return .text(text)
            }
            return .ignore
        case "message_stop":
            return .stop
        case "error":
            let err = obj["error"] as? [String: Any]
            let type = err?["type"] as? String ?? "error"
            let msg = err?["message"] as? String ?? ""
            throw LLMError.stream("\(type): \(msg)")
        default:
            return .ignore  // message_start, content_block_start/stop, message_delta, ping, thinking deltas
        }
    }

    public static func interpret(sse: SSEEvent) throws -> StreamAction {
        try interpret(json: Data(sse.data.utf8))
    }
}

// MARK: - OpenAI chat.completions stream chunks

public enum OpenAIStreamParser {
    /// Interprets one SSE `data:` payload. `[DONE]` → `.stop`.
    public static func interpret(data: String) throws -> StreamAction {
        let trimmed = data.trimmingCharacters(in: .whitespaces)
        if trimmed == "[DONE]" { return .stop }
        guard let obj = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8)) as? [String: Any] else {
            throw LLMError.stream("malformed chunk JSON: \(String(trimmed.prefix(200)))")
        }
        if let err = obj["error"] {
            if let e = err as? [String: Any] {
                throw LLMError.stream((e["message"] as? String) ?? "\(e)")
            }
            throw LLMError.stream("\(err)")
        }
        guard let choices = obj["choices"] as? [[String: Any]], let first = choices.first,
              let delta = first["delta"] as? [String: Any],
              let content = delta["content"] as? String, !content.isEmpty else {
            return .ignore
        }
        return .text(content)
    }
}

// MARK: - AWS event stream (application/vnd.amazon.eventstream)

public struct EventStreamMessage: Sendable, Equatable {
    public var headers: [String: String]
    public var payload: Data
}

/// Incremental decoder for AWS binary event-stream framing:
/// [total len u32][headers len u32][prelude CRC u32][headers][payload][message CRC u32], big-endian.
public struct EventStreamDecoder: Sendable {
    private var buffer: [UInt8] = []
    private var expected: Int?

    public init() {}

    public mutating func feed(_ byte: UInt8) throws -> EventStreamMessage? {
        buffer.append(byte)
        if expected == nil, buffer.count == 12 {
            let total = Int(Self.u32(buffer, 0))
            let preludeCRC = Self.u32(buffer, 8)
            guard CRC32.checksum(buffer[0..<8]) == preludeCRC else { throw LLMError.stream("event-stream prelude CRC mismatch") }
            guard total >= 16, total <= 16 * 1024 * 1024 else { throw LLMError.stream("event-stream bad frame length \(total)") }
            expected = total
        }
        guard let total = expected, buffer.count == total else { return nil }
        defer { buffer.removeAll(keepingCapacity: true); expected = nil }
        return try Self.decodeFrame(buffer)
    }

    public mutating func feed<S: Sequence>(_ bytes: S) throws -> [EventStreamMessage] where S.Element == UInt8 {
        var out: [EventStreamMessage] = []
        for b in bytes { if let m = try feed(b) { out.append(m) } }
        return out
    }

    static func decodeFrame(_ f: [UInt8]) throws -> EventStreamMessage {
        let total = f.count
        let headersLen = Int(u32(f, 4))
        let msgCRC = u32(f, total - 4)
        guard CRC32.checksum(f[0..<(total - 4)]) == msgCRC else { throw LLMError.stream("event-stream message CRC mismatch") }
        guard 12 + headersLen <= total - 4 else { throw LLMError.stream("event-stream bad headers length") }
        var headers: [String: String] = [:]
        var i = 12
        let hEnd = 12 + headersLen
        while i < hEnd {
            let nameLen = Int(f[i]); i += 1
            let name = String(decoding: f[i..<(i + nameLen)], as: UTF8.self); i += nameLen
            let type = f[i]; i += 1
            switch type {
            case 0: headers[name] = "true"
            case 1: headers[name] = "false"
            case 2: headers[name] = String(Int8(bitPattern: f[i])); i += 1
            case 3: headers[name] = String(Int16(bitPattern: UInt16(f[i]) << 8 | UInt16(f[i + 1]))); i += 2
            case 4: headers[name] = String(Int32(bitPattern: u32(f, i))); i += 4
            case 5, 8:
                var v: UInt64 = 0
                for k in 0..<8 { v = v << 8 | UInt64(f[i + k]) }
                headers[name] = String(Int64(bitPattern: v)); i += 8
            case 6, 7:
                let len = Int(UInt16(f[i]) << 8 | UInt16(f[i + 1])); i += 2
                headers[name] = type == 7 ? String(decoding: f[i..<(i + len)], as: UTF8.self)
                                          : Data(f[i..<(i + len)]).base64EncodedString()
                i += len
            case 9: headers[name] = Data(f[i..<(i + 16)]).map { String(format: "%02x", $0) }.joined(); i += 16
            default: throw LLMError.stream("event-stream unknown header type \(type)")
            }
        }
        return EventStreamMessage(headers: headers, payload: Data(f[hEnd..<(total - 4)]))
    }

    static func u32(_ b: [UInt8], _ o: Int) -> UInt32 {
        UInt32(b[o]) << 24 | UInt32(b[o + 1]) << 16 | UInt32(b[o + 2]) << 8 | UInt32(b[o + 3])
    }

    /// Encoder (string headers only) — used by the self-test to build canned frames.
    public static func encode(headers: [(String, String)], payload: Data) -> [UInt8] {
        var h: [UInt8] = []
        for (name, value) in headers {
            let n = Array(name.utf8), v = Array(value.utf8)
            h.append(UInt8(n.count)); h += n; h.append(7)
            h.append(UInt8(v.count >> 8)); h.append(UInt8(v.count & 0xff)); h += v
        }
        let total = 12 + h.count + payload.count + 4
        func be(_ x: UInt32) -> [UInt8] { [UInt8(x >> 24), UInt8(x >> 16 & 0xff), UInt8(x >> 8 & 0xff), UInt8(x & 0xff)] }
        var f = be(UInt32(total)) + be(UInt32(h.count))
        f += be(CRC32.checksum(f[0..<8]))
        f += h
        f += payload
        f += be(CRC32.checksum(f[0..<f.count]))
        return f
    }
}

/// Bedrock-specific interpretation of one decoded event-stream message.
public enum BedrockStreamParser {
    public static func interpret(_ msg: EventStreamMessage) throws -> StreamAction {
        let type = msg.headers[":message-type"] ?? "event"
        switch type {
        case "event":
            guard msg.headers[":event-type"] ?? "chunk" == "chunk" else { return .ignore }
            guard let obj = try? JSONSerialization.jsonObject(with: msg.payload) as? [String: Any],
                  let b64 = obj["bytes"] as? String, let inner = Data(base64Encoded: b64) else {
                throw LLMError.stream("bad Bedrock chunk payload")
            }
            return try AnthropicStreamParser.interpret(json: inner)
        case "exception":
            let exType = msg.headers[":exception-type"] ?? "exception"
            throw LLMError.stream("\(exType): \(LLMHTTP.errorMessage(from: msg.payload))")
        default:
            let code = msg.headers[":error-code"] ?? type
            let text = msg.headers[":error-message"] ?? LLMHTTP.errorMessage(from: msg.payload)
            throw LLMError.stream("\(code): \(text)")
        }
    }
}

enum CRC32 {
    static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func checksum<C: Collection>(_ bytes: C) -> UInt32 where C.Element == UInt8 {
        var c: UInt32 = 0xFFFF_FFFF
        for b in bytes { c = table[Int((c ^ UInt32(b)) & 0xff)] ^ (c >> 8) }
        return c ^ 0xFFFF_FFFF
    }
}
