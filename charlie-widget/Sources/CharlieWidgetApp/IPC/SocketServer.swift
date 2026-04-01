import Foundation
import Network

/// Unix domain socket server listening on `/tmp/charlie-widget.sock`.
/// Receives newline-delimited JSON commands from CLI clients.
@MainActor
final class SocketServer: Sendable {

    // MARK: - Types

    enum Command {
        case toast(title: String, subtitle: String?, body: String, level: ToastLevel)
        case history
        case clear
    }

    // MARK: - Configuration

    static let socketPath = "/tmp/charlie-widget.sock"

    // MARK: - Callbacks

    var onToast: (@MainActor @Sendable (String, String?, String, ToastLevel) -> Void)?
    var onHistoryRequest: (@MainActor @Sendable (NWConnection) -> Void)?
    var onClearRequest: (@MainActor @Sendable () -> Void)?

    // MARK: - Private state

    private var listener: NWListener?
    private var connections: [NWConnection] = []

    // MARK: - Lifecycle

    func start() {
        removeStaleSocket()

        let params = NWParameters()
        params.defaultProtocolStack.transportProtocol = NWProtocolTCP.Options()
        params.requiredLocalEndpoint = NWEndpoint.unix(path: Self.socketPath)

        do {
            let nwListener = try NWListener(using: params)

            nwListener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    self?.handleListenerState(state)
                }
            }

            nwListener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.handleNewConnection(connection)
                }
            }

            nwListener.start(queue: .main)
            self.listener = nwListener
        } catch {
            print("[SocketServer] Failed to create listener: \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        for conn in connections {
            conn.cancel()
        }
        connections.removeAll()
        removeStaleSocket()
    }

    /// Send a string back to a client connection, then close it.
    func send(_ string: String, to connection: NWConnection) {
        guard let data = string.data(using: .utf8) else { return }
        connection.send(
            content: data,
            contentContext: .finalMessage,
            isComplete: true,
            completion: .contentProcessed { _ in
                connection.cancel()
            }
        )
    }

    // MARK: - Private helpers

    private func removeStaleSocket() {
        let path = Self.socketPath
        if FileManager.default.fileExists(atPath: path) {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            print("[SocketServer] Listening on \(Self.socketPath)")
        case .failed(let error):
            print("[SocketServer] Listener failed: \(error)")
            stop()
        case .cancelled:
            print("[SocketServer] Listener cancelled")
        default:
            break
        }
    }

    private func handleNewConnection(_ connection: NWConnection) {
        connections.append(connection)

        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                if case .cancelled = state {
                    self?.connections.removeAll { $0 === connection }
                } else if case .failed = state {
                    self?.connections.removeAll { $0 === connection }
                }
            }
        }

        connection.start(queue: .main)
        receiveData(on: connection)
    }

    private func receiveData(on connection: NWConnection) {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 65536
        ) { [weak self] content, _, isComplete, error in
            Task { @MainActor in
                guard let self else { return }

                if let data = content, !data.isEmpty {
                    self.processData(data, from: connection)
                }

                if let error {
                    print("[SocketServer] Receive error: \(error)")
                    connection.cancel()
                    return
                }

                if isComplete {
                    // Client closed its end; nothing more to read.
                    return
                }

                // Keep reading for additional lines.
                self.receiveData(on: connection)
            }
        }
    }

    private func processData(_ data: Data, from connection: NWConnection) {
        guard let text = String(data: data, encoding: .utf8) else { return }

        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        for line in lines {
            processLine(String(line), from: connection)
        }
    }

    private func processLine(_ line: String, from connection: NWConnection) {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let command = json["command"] as? String
        else {
            send("{\"error\":\"invalid JSON\"}\n", to: connection)
            return
        }

        switch command {
        case "toast":
            let title = json["title"] as? String ?? "Charlie Widget"
            let subtitle = json["subtitle"] as? String
            let body = json["body"] as? String ?? ""
            let levelStr = json["level"] as? String ?? "info"
            let level = ToastLevel(rawValue: levelStr) ?? .info
            onToast?(title, subtitle, body, level)
            send("{\"ok\":true}\n", to: connection)

        case "history":
            onHistoryRequest?(connection)

        case "clear":
            onClearRequest?()
            send("{\"ok\":true}\n", to: connection)

        default:
            send("{\"error\":\"unknown command: \(command)\"}\n", to: connection)
        }
    }
}
