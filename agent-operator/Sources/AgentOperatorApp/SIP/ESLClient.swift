import Foundation
import Network

// MARK: - Delegate protocol

/// Receives call lifecycle events from the ESL client.
protocol ESLDelegate: AnyObject, Sendable {
    func callStarted(channelId: String)
    func callEnded(channelId: String)
}

// MARK: - ESLClient

/// Connects to FreeSWITCH via the Event Socket Library (ESL) protocol,
/// subscribes to call events, and notifies a delegate when calls to
/// extension 6000 start and end.
///
/// FreeSWITCH records audio to `/tmp/voicebot_<uuid>.wav` via the dialplan.
/// The recording path is stored in `lastRecordingPath` for downstream
/// consumers to read when the call ends.
///
/// Uses `NWConnection` from the Network framework (no external dependencies).
final class ESLClient: Sendable {

    // MARK: - Configuration

    struct Config: Sendable {
        let host: String
        let port: UInt16
        let password: String

        /// Default configuration for local FreeSWITCH.
        static let local = Config(host: "127.0.0.1", port: 8021, password: "ClueCon")
    }

    // MARK: - State (guarded by lock)

    private let state = ESLState()

    /// Mutable state isolated behind `NSLock` for `Sendable` compliance.
    private final class ESLState: @unchecked Sendable {
        private let lock = NSLock()

        private var _connection: NWConnection?
        private var _delegate: ESLDelegate?
        private var _activeCallUUID: String?
        private var _lastRecordingPath: String?
        private var _authenticated = false
        private var _buffer = Data()

        var connection: NWConnection? {
            get { lock.withLock { _connection } }
            set { lock.withLock { _connection = newValue } }
        }
        var delegate: ESLDelegate? {
            get { lock.withLock { _delegate } }
            set { lock.withLock { _delegate = newValue } }
        }
        var activeCallUUID: String? {
            get { lock.withLock { _activeCallUUID } }
            set { lock.withLock { _activeCallUUID = newValue } }
        }
        var lastRecordingPath: String? {
            get { lock.withLock { _lastRecordingPath } }
            set { lock.withLock { _lastRecordingPath = newValue } }
        }
        var authenticated: Bool {
            get { lock.withLock { _authenticated } }
            set { lock.withLock { _authenticated = newValue } }
        }

        // Buffer management needs atomic read-modify-write.
        func appendToBuffer(_ data: Data) {
            lock.withLock { _buffer.append(data) }
        }
        func drainBuffer() -> Data {
            lock.withLock {
                let copy = _buffer
                _buffer.removeAll()
                return copy
            }
        }
        func peekBuffer() -> Data {
            lock.withLock { _buffer }
        }
        func replaceBuffer(_ data: Data) {
            lock.withLock { _buffer = data }
        }
    }

    // MARK: - Public properties

    private let config: Config

    var delegate: ESLDelegate? {
        get { state.delegate }
        set { state.delegate = newValue }
    }

    var lastRecordingPath: String? {
        state.lastRecordingPath
    }

    // MARK: - Init

    init(config: Config = .local) {
        self.config = config
    }

    // MARK: - Connect

    /// Open a TCP connection to FreeSWITCH ESL, authenticate, and subscribe
    /// to call events.
    func connect() async throws {
        let host = NWEndpoint.Host(config.host)
        let port = NWEndpoint.Port(rawValue: config.port)!
        let connection = NWConnection(host: host, port: port, using: .tcp)

        state.connection = connection

        // Wait for the connection to become ready.
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, any Error>) in
            connection.stateUpdateHandler = { newState in
                switch newState {
                case .ready:
                    cont.resume()
                case .failed(let error):
                    cont.resume(throwing: error)
                case .cancelled:
                    cont.resume(throwing: ESLError.connectionCancelled)
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
        }

        print("[ESL] Connected to \(config.host):\(config.port)")

        // FreeSWITCH sends "Content-Type: auth/request" on connect.
        let authRequest = try await readResponse(on: connection)
        guard authRequest.contains("auth/request") else {
            throw ESLError.unexpectedResponse(authRequest)
        }

        // Authenticate.
        try await send("auth \(config.password)\n\n", on: connection)
        let authReply = try await readResponse(on: connection)
        guard authReply.contains("Reply-Text: +OK") else {
            throw ESLError.authFailed(authReply)
        }
        state.authenticated = true
        print("[ESL] Authenticated")

        // Subscribe to relevant events.
        try await send("event plain CHANNEL_ANSWER CHANNEL_HANGUP\n\n", on: connection)
        let eventReply = try await readResponse(on: connection)
        guard eventReply.contains("Reply-Text: +OK") else {
            throw ESLError.unexpectedResponse(eventReply)
        }
        print("[ESL] Subscribed to CHANNEL_ANSWER, CHANNEL_HANGUP")

        // Start the receive loop.
        Task { [weak self] in
            await self?.receiveLoop(on: connection)
        }
    }

    /// Close the ESL connection.
    func disconnect() {
        state.connection?.cancel()
        state.connection = nil
        state.authenticated = false
        state.activeCallUUID = nil
        print("[ESL] Disconnected")
    }

    // MARK: - Errors

    enum ESLError: Error, CustomStringConvertible {
        case connectionCancelled
        case unexpectedResponse(String)
        case authFailed(String)
        case sendFailed
        case receiveTimeout

        var description: String {
            switch self {
            case .connectionCancelled:
                return "ESL connection was cancelled"
            case .unexpectedResponse(let resp):
                return "Unexpected ESL response: \(resp)"
            case .authFailed(let resp):
                return "ESL auth failed: \(resp)"
            case .sendFailed:
                return "Failed to send data over ESL connection"
            case .receiveTimeout:
                return "ESL receive timed out"
            }
        }
    }

    // MARK: - Send

    /// Send a raw ESL command string over the connection.
    private func send(_ command: String, on connection: NWConnection) async throws {
        let data = Data(command.utf8)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, any Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume()
                }
            })
        }
    }

    // MARK: - Read a single ESL response

    /// Read data from the connection until we get a complete ESL message
    /// (terminated by a blank line `\n\n`).
    private func readResponse(on connection: NWConnection) async throws -> String {
        var accumulated = Data()
        let separator = Data("\n\n".utf8)

        while true {
            let chunk: Data = try await withCheckedThrowingContinuation { cont in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { content, _, _, error in
                    if let error {
                        cont.resume(throwing: error)
                    } else if let content, !content.isEmpty {
                        cont.resume(returning: content)
                    } else {
                        cont.resume(returning: Data())
                    }
                }
            }

            accumulated.append(chunk)

            // Check if we have a complete message (ends with \n\n).
            if let _ = accumulated.range(of: separator) {
                return String(data: accumulated, encoding: .utf8) ?? ""
            }
        }
    }

    // MARK: - Receive loop

    /// Continuously receive ESL event data and parse complete event blocks.
    private func receiveLoop(on connection: NWConnection) async {
        while true {
            let chunk: Data?
            do {
                chunk = try await withCheckedThrowingContinuation { cont in
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { content, _, _, error in
                        if let error {
                            cont.resume(throwing: error)
                        } else {
                            cont.resume(returning: content)
                        }
                    }
                }
            } catch {
                print("[ESL] Receive error: \(error)")
                break
            }

            guard let data = chunk, !data.isEmpty else {
                print("[ESL] Connection closed by server")
                break
            }

            state.appendToBuffer(data)
            processBuffer()
        }
    }

    // MARK: - Buffer processing

    /// Extract complete ESL event blocks from the buffer and handle each one.
    /// ESL events are blocks of `Key: Value\n` lines terminated by `\n\n`.
    private func processBuffer() {
        let separator = Data("\n\n".utf8)

        while true {
            let current = state.peekBuffer()
            guard let range = current.range(of: separator) else { break }

            let blockData = current[current.startIndex..<range.lowerBound]
            let remaining = current[range.upperBound...]

            state.replaceBuffer(Data(remaining))

            guard let block = String(data: blockData, encoding: .utf8) else { continue }
            handleEventBlock(block)
        }
    }

    // MARK: - Event parsing

    /// Parse an ESL event block into a key-value dictionary and dispatch.
    private func handleEventBlock(_ block: String) {
        var headers: [String: String] = [:]

        for line in block.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // ESL headers are "Key: Value"
            if let colonIndex = trimmed.firstIndex(of: ":") {
                let key = String(trimmed[trimmed.startIndex..<colonIndex])
                    .trimmingCharacters(in: .whitespaces)
                let value = String(trimmed[trimmed.index(after: colonIndex)...])
                    .trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }

        guard let contentType = headers["Content-Type"] else { return }

        // We only care about event/plain blocks.
        if contentType == "text/event-plain" {
            handlePlainEvent(headers)
        }
    }

    /// Handle a parsed ESL plain event.
    private func handlePlainEvent(_ headers: [String: String]) {
        guard let eventName = headers["Event-Name"] else { return }

        let uuid = headers["Channel-Call-UUID"]
            ?? headers["Unique-ID"]
            ?? ""

        let destination = headers["Caller-Destination-Number"] ?? ""

        switch eventName {
        case "CHANNEL_ANSWER":
            // Only act on calls to extension 6000.
            guard destination == "6000" else {
                print("[ESL] CHANNEL_ANSWER for \(destination) — ignoring")
                return
            }

            print("[ESL] CHANNEL_ANSWER — uuid=\(uuid) dest=\(destination)")
            state.activeCallUUID = uuid
            state.lastRecordingPath = "/tmp/voicebot_\(uuid).wav"
            state.delegate?.callStarted(channelId: uuid)

        case "CHANNEL_HANGUP":
            // Only act if this is the call we're tracking.
            guard uuid == state.activeCallUUID else { return }

            print("[ESL] CHANNEL_HANGUP — uuid=\(uuid)")
            state.delegate?.callEnded(channelId: uuid)
            state.activeCallUUID = nil

        default:
            break
        }
    }
}
