import Foundation

// MARK: - Delegate protocol

/// Receives call lifecycle events from the ARI client.
protocol ARIDelegate: AnyObject, Sendable {
    func callStarted(channelId: String)
    func callEnded(channelId: String)
}

// MARK: - ARIClient

/// Connects to Asterisk's ARI over WebSocket, handles Stasis events, and
/// manages bridges/channels for external media.
///
/// Uses only Foundation (URLSession) — no external dependencies.
final class ARIClient: Sendable {

    // MARK: - Configuration

    struct Config: Sendable {
        let host: String
        let port: Int
        let app: String
        let username: String
        let password: String
        /// Local UDP port where RTPListener is bound.
        let rtpPort: UInt16

        /// Default configuration for local development.
        static let local = Config(
            host: "127.0.0.1",
            port: 8088,
            app: "voicebot",
            username: "voicebot",
            password: "voicebot123",
            rtpPort: 7078
        )

        var wsURL: URL {
            URL(string: "ws://\(host):\(port)/ari/events?app=\(app)&api_key=\(username):\(password)")!
        }

        var baseURL: String { "http://\(host):\(port)/ari" }

        var authHeader: String {
            let credentials = "\(username):\(password)"
            let encoded = Data(credentials.utf8).base64EncodedString()
            return "Basic \(encoded)"
        }
    }

    // MARK: - State (guarded by lock)

    private let state = ARIState()

    /// Mutable state isolated behind `NSLock` for `Sendable` compliance.
    private final class ARIState: @unchecked Sendable {
        private let lock = NSLock()

        private var _webSocketTask: URLSessionWebSocketTask?
        private var _bridgeId: String?
        private var _externalChannelId: String?
        private var _incomingChannelId: String?
        private var _delegate: ARIDelegate?

        var webSocketTask: URLSessionWebSocketTask? {
            get { lock.withLock { _webSocketTask } }
            set { lock.withLock { _webSocketTask = newValue } }
        }
        var bridgeId: String? {
            get { lock.withLock { _bridgeId } }
            set { lock.withLock { _bridgeId = newValue } }
        }
        var externalChannelId: String? {
            get { lock.withLock { _externalChannelId } }
            set { lock.withLock { _externalChannelId = newValue } }
        }
        var incomingChannelId: String? {
            get { lock.withLock { _incomingChannelId } }
            set { lock.withLock { _incomingChannelId = newValue } }
        }
        var delegate: ARIDelegate? {
            get { lock.withLock { _delegate } }
            set { lock.withLock { _delegate = newValue } }
        }
    }

    // MARK: - Public properties

    private let config: Config

    var delegate: ARIDelegate? {
        get { state.delegate }
        set { state.delegate = newValue }
    }

    // MARK: - Init

    init(config: Config = .local) {
        self.config = config
    }

    // MARK: - Connect

    /// Open the ARI WebSocket and begin listening for events.
    func connect() {
        let request = URLRequest(url: config.wsURL)
        let task = URLSession.shared.webSocketTask(with: request)
        state.webSocketTask = task
        task.resume()
        print("[ARI] WebSocket connecting to \(config.wsURL.absoluteString)")
        scheduleReceive()
    }

    /// Close the WebSocket connection.
    func disconnect() {
        state.webSocketTask?.cancel(with: .goingAway, reason: nil)
        state.webSocketTask = nil
        print("[ARI] WebSocket disconnected")
    }

    // MARK: - WebSocket receive loop

    private func scheduleReceive() {
        state.webSocketTask?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleEvent(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleEvent(text)
                    }
                @unknown default:
                    break
                }
                self.scheduleReceive()

            case .failure(let error):
                print("[ARI] WebSocket receive error: \(error)")
            }
        }
    }

    // MARK: - Event handling

    private func handleEvent(_ json: String) {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String
        else { return }

        switch type {
        case "StasisStart":
            guard let channel = obj["channel"] as? [String: Any],
                  let channelId = channel["id"] as? String
            else { return }

            // Ignore our own externalMedia channels re-entering Stasis.
            if channelId == state.externalChannelId { return }

            print("[ARI] StasisStart — channel \(channelId)")
            state.incomingChannelId = channelId
            state.delegate?.callStarted(channelId: channelId)

            Task { await self.setupBridge(incomingChannelId: channelId) }

        case "StasisEnd":
            guard let channel = obj["channel"] as? [String: Any],
                  let channelId = channel["id"] as? String
            else { return }

            print("[ARI] StasisEnd — channel \(channelId)")

            // Only act on the incoming channel ending.
            if channelId == state.incomingChannelId {
                state.delegate?.callEnded(channelId: channelId)
                Task { await self.tearDown() }
            }

        default:
            break
        }
    }

    // MARK: - Bridge setup

    /// Create a bridge, add the incoming channel, create an externalMedia
    /// channel, and add it to the bridge.
    private func setupBridge(incomingChannelId: String) async {
        do {
            // 1. Create bridge.
            let bridgeData = try await ariPOST(
                path: "/bridges",
                body: ["type": "mixing"]
            )
            guard let bridgeId = bridgeData["id"] as? String else {
                print("[ARI] Failed to read bridge id")
                return
            }
            state.bridgeId = bridgeId
            print("[ARI] Created bridge \(bridgeId)")

            // 2. Add incoming channel to bridge.
            _ = try await ariPOST(
                path: "/bridges/\(bridgeId)/addChannel",
                body: ["channel": incomingChannelId]
            )
            print("[ARI] Added incoming channel to bridge")

            // 3. Create externalMedia channel.
            let extData = try await ariPOST(
                path: "/channels/externalMedia",
                body: [
                    "app": config.app,
                    "external_host": "127.0.0.1:\(config.rtpPort)",
                    "format": "ulaw",
                ]
            )
            guard let extChannel = extData["channel"] as? [String: Any],
                  let extId = extChannel["id"] as? String
            else {
                // Some ARI versions return the channel at top level.
                if let extId = extData["id"] as? String {
                    state.externalChannelId = extId
                    print("[ARI] Created externalMedia channel \(extId)")
                } else {
                    print("[ARI] Failed to read externalMedia channel id")
                    return
                }
                // Fall through to add it.
                let extChannelId = state.externalChannelId!
                _ = try await ariPOST(
                    path: "/bridges/\(bridgeId)/addChannel",
                    body: ["channel": extChannelId]
                )
                print("[ARI] Added externalMedia channel to bridge")
                return
            }
            state.externalChannelId = extId
            print("[ARI] Created externalMedia channel \(extId)")

            // 4. Add externalMedia channel to bridge.
            _ = try await ariPOST(
                path: "/bridges/\(bridgeId)/addChannel",
                body: ["channel": extId]
            )
            print("[ARI] Added externalMedia channel to bridge")

        } catch {
            print("[ARI] Bridge setup error: \(error)")
        }
    }

    // MARK: - Teardown

    /// Destroy the bridge and hang up the externalMedia channel.
    private func tearDown() async {
        if let extId = state.externalChannelId {
            _ = try? await ariDELETE(path: "/channels/\(extId)")
            state.externalChannelId = nil
            print("[ARI] Hung up externalMedia channel")
        }

        if let bridgeId = state.bridgeId {
            _ = try? await ariDELETE(path: "/bridges/\(bridgeId)")
            state.bridgeId = nil
            print("[ARI] Destroyed bridge")
        }

        state.incomingChannelId = nil
    }

    // MARK: - ARI REST helpers

    /// POST to an ARI endpoint with a JSON body. Returns the parsed response.
    @discardableResult
    private func ariPOST(
        path: String,
        body: [String: Any]
    ) async throws -> [String: Any] {
        let url = URL(string: config.baseURL + path)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(config.authHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let text = String(data: data, encoding: .utf8) ?? "<no body>"
            print("[ARI] POST \(path) → \(http.statusCode): \(text)")
        }

        if data.isEmpty { return [:] }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    /// DELETE to an ARI endpoint.
    @discardableResult
    private func ariDELETE(path: String) async throws -> Data {
        let url = URL(string: config.baseURL + path)!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue(config.authHeader, forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let text = String(data: data, encoding: .utf8) ?? "<no body>"
            print("[ARI] DELETE \(path) → \(http.statusCode): \(text)")
        }

        return data
    }
}
