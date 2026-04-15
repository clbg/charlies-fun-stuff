import Foundation
import Network

/// CLI entry point for sending commands to CharlieWidget via Unix domain socket.
@main
struct CLI {

    static let socketPath = "/tmp/charlie-widget.sock"

    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())

        guard let subcommand = args.first else {
            printUsage()
            exit(1)
        }

        switch subcommand {
        case "toast":
            await handleToast(Array(args.dropFirst()))
        case "sessions":
            handleSessions(Array(args.dropFirst()))
        case "record":
            await handleRecord(Array(args.dropFirst()))
        default:
            fputs("Unknown command: \(subcommand)\n", stderr)
            printUsage()
            exit(1)
        }
    }

    // MARK: - Toast subcommand

    private static func handleToast(_ args: [String]) async {
        // Check for flag-based variants first
        if args.contains("--history") {
            let json = #"{"command":"history"}"# + "\n"
            await sendAndPrintResponse(json)
            return
        }

        if args.contains("--clear") {
            let json = #"{"command":"clear"}"# + "\n"
            await sendAndExpectOK(json)
            return
        }

        // Build a toast command
        var title = "Charlie Widget"
        var subtitle: String?
        var body: String?
        var level = "info"

        var i = 0
        var positionalArgs: [String] = []

        while i < args.count {
            switch args[i] {
            case "--title":
                i += 1
                guard i < args.count else {
                    fputs("--title requires a value\n", stderr)
                    exit(1)
                }
                title = args[i]
            case "--subtitle":
                i += 1
                guard i < args.count else {
                    fputs("--subtitle requires a value\n", stderr)
                    exit(1)
                }
                subtitle = args[i]
            case "--body":
                i += 1
                guard i < args.count else {
                    fputs("--body requires a value\n", stderr)
                    exit(1)
                }
                body = args[i]
            case "--level":
                i += 1
                guard i < args.count else {
                    fputs("--level requires a value (info|success|warning|error)\n", stderr)
                    exit(1)
                }
                level = args[i]
            default:
                positionalArgs.append(args[i])
            }
            i += 1
        }

        // If there are positional args and no explicit body, use the first positional as body
        if body == nil, let first = positionalArgs.first {
            body = first
        }

        guard let body else {
            fputs("Error: toast requires a message body\n", stderr)
            printUsage()
            exit(1)
        }

        var dict: [String: String] = [
            "command": "toast",
            "title": title,
            "body": body,
            "level": level,
        ]
        if let subtitle {
            dict["subtitle"] = subtitle
        }

        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let json = String(data: data, encoding: .utf8)
        else {
            fputs("Error: failed to encode JSON\n", stderr)
            exit(1)
        }

        await sendAndExpectOK(json + "\n")
    }

    // MARK: - Sessions subcommand

    private static func handleSessions(_ args: [String]) {
        let sessionsDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("CharlieWidget", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)

        if args.contains("--clear") {
            let fm = FileManager.default
            if let files = try? fm.contentsOfDirectory(at: sessionsDir, includingPropertiesForKeys: nil) {
                for file in files where file.pathExtension == "json" {
                    try? fm.removeItem(at: file)
                }
            }
            print("Sessions cleared")
            return
        }

        // List sessions as JSON
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: sessionsDir, includingPropertiesForKeys: nil) else {
            print("[]")
            return
        }

        var sessions: [[String: Any]] = []
        for file in files where file.pathExtension == "json" && !file.lastPathComponent.hasPrefix(".") {
            if let data = try? Data(contentsOf: file),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                sessions.append(json)
            }
        }

        if let data = try? JSONSerialization.data(withJSONObject: sessions, options: .prettyPrinted),
           let output = String(data: data, encoding: .utf8) {
            print(output)
        } else {
            print("[]")
        }
    }

    // MARK: - Record subcommand

    private static func handleRecord(_ args: [String]) async {
        guard let action = args.first else {
            fputs("Usage: charlie-widget record <start|stop|status|list>\n", stderr)
            exit(1)
        }

        switch action {
        case "start":
            let source = args.contains("--mic-only") ? "mic-only" : "system+mic"
            let json = "{\"command\":\"record_start\",\"source\":\"\(source)\"}\n"
            let response = await sendMessage(json)
            if let response {
                if response.contains("\"ok\":true") || response.contains("\"ok\": true") {
                    print("Recording started (\(source))")
                } else {
                    fputs("Error: \(response)\n", stderr)
                    exit(1)
                }
            }

        case "stop":
            let json = "{\"command\":\"record_stop\"}\n"
            let response = await sendMessage(json)
            if let response {
                if response.contains("\"ok\":true") || response.contains("\"ok\": true") {
                    print("Recording stopped")
                } else {
                    fputs("Error: \(response)\n", stderr)
                    exit(1)
                }
            }

        case "status":
            await sendAndPrintResponse("{\"command\":\"record_status\"}\n")

        case "list":
            await sendAndPrintResponse("{\"command\":\"record_list\"}\n")

        default:
            fputs("Unknown record action: \(action)\n", stderr)
            fputs("Usage: charlie-widget record <start|stop|status|list>\n", stderr)
            exit(1)
        }
    }

    // MARK: - Socket communication

    private static func sendAndExpectOK(_ message: String) async {
        let response = await sendMessage(message)
        if let response, !response.isEmpty {
            // Silently succeed if ok, otherwise print
            if !response.contains("\"ok\":true") && !response.contains("\"ok\": true") {
                print(response)
            }
        }
    }

    private static func sendAndPrintResponse(_ message: String) async {
        let response = await sendMessage(message)
        if let response {
            print(response)
        }
    }

    private static func sendMessage(_ message: String) async -> String? {
        guard FileManager.default.fileExists(atPath: socketPath) else {
            fputs("Error: CharlieWidget is not running (socket not found at \(socketPath))\n", stderr)
            exit(1)
        }

        let endpoint = NWEndpoint.unix(path: socketPath)
        let connection = NWConnection(to: endpoint, using: .tcp)

        return await withCheckedContinuation { continuation in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard let data = message.data(using: .utf8) else {
                        connection.cancel()
                        continuation.resume(returning: nil)
                        return
                    }
                    connection.send(
                        content: data,
                        contentContext: .defaultMessage,
                        isComplete: false,
                        completion: .contentProcessed { error in
                            if let error {
                                fputs("Error sending: \(error)\n", stderr)
                                connection.cancel()
                                continuation.resume(returning: nil)
                                return
                            }

                            // Now read the response
                            connection.receive(
                                minimumIncompleteLength: 1,
                                maximumLength: 65536
                            ) { responseData, _, _, recvError in
                                defer { connection.cancel() }

                                if let recvError {
                                    fputs("Error receiving: \(recvError)\n", stderr)
                                    continuation.resume(returning: nil)
                                    return
                                }

                                if let responseData,
                                   let text = String(data: responseData, encoding: .utf8) {
                                    continuation.resume(
                                        returning: text.trimmingCharacters(in: .whitespacesAndNewlines)
                                    )
                                } else {
                                    continuation.resume(returning: nil)
                                }
                            }
                        }
                    )

                case .failed(let error):
                    fputs("Error: could not connect to CharlieWidget (\(error))\n", stderr)
                    connection.cancel()
                    continuation.resume(returning: nil)
                    Foundation.exit(1)

                case .cancelled:
                    break

                default:
                    break
                }
            }

            connection.start(queue: .global())

            // Timeout after 5 seconds
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                if connection.state != .cancelled {
                    fputs("Error: connection timed out\n", stderr)
                    connection.cancel()
                    continuation.resume(returning: nil)
                    Foundation.exit(1)
                }
            }
        }
    }

    // MARK: - Usage

    private static func printUsage() {
        let usage = """
        Usage:
          charlie-widget toast "message"
          charlie-widget toast --title "T" --subtitle "S" --body "B" --level "success"
          charlie-widget toast --history
          charlie-widget toast --clear
          charlie-widget sessions              List active agent sessions (JSON)
          charlie-widget sessions --clear      Remove all session state files
          charlie-widget record start          Start recording (system audio + mic)
          charlie-widget record start --mic-only  Start recording (mic only)
          charlie-widget record stop           Stop recording
          charlie-widget record status         Current recording state
          charlie-widget record list           List today's recordings
        """
        fputs(usage + "\n", stderr)
    }
}
