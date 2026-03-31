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
          charlie-widget toast --title "T" --subtitle "S" --body "B"
          charlie-widget toast --history
          charlie-widget toast --clear
        """
        fputs(usage + "\n", stderr)
    }
}
