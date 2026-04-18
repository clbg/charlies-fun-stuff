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
        case "voice":
            await handleVoice(Array(args.dropFirst()))
        case "bubble":
            await handleBubble(Array(args.dropFirst()))
        case "music":
            await handleMusic(Array(args.dropFirst()))
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
            var source = "both"
            if args.contains("--mic") { source = "mic" }
            else if args.contains("--system") { source = "system" }
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

        case "play":
            // Play recording(s) via mpv with multi-track support
            // Usage: charlie-widget record play [--track 1|2|both] [recording-id]
            var track = "both"
            var targetId: String?
            var i = 1
            while i < args.count {
                switch args[i] {
                case "--track":
                    i += 1
                    if i < args.count { track = args[i] }
                case "--mic": track = "2"
                case "--system": track = "1"
                default:
                    targetId = args[i]
                }
                i += 1
            }

            // Find the recording file
            let recDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("CharlieWidget/recordings", isDirectory: true)
            let today = {
                let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
                return f.string(from: Date())
            }()
            let dayDir = recDir.appendingPathComponent(today)

            // If ID given, find exact file; otherwise use latest
            var m4aFile: String?
            if let id = targetId {
                // Search JSON files for matching ID
                if let files = try? FileManager.default.contentsOfDirectory(at: dayDir, includingPropertiesForKeys: nil) {
                    for f in files where f.pathExtension == "json" {
                        if let data = try? Data(contentsOf: f), let s = String(data: data, encoding: .utf8), s.contains(id) {
                            m4aFile = dayDir.appendingPathComponent(f.deletingPathExtension().lastPathComponent + ".m4a").path
                            break
                        }
                    }
                }
            } else {
                // Latest .m4a
                if let files = try? FileManager.default.contentsOfDirectory(at: dayDir, includingPropertiesForKeys: [.contentModificationDateKey]) {
                    m4aFile = files.filter { $0.pathExtension == "m4a" }
                        .sorted { (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast >
                                  (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast }
                        .first?.path
                }
            }

            guard let file = m4aFile, FileManager.default.fileExists(atPath: file) else {
                fputs("No recording found\n", stderr)
                exit(1)
            }

            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/mpv")
            switch track {
            case "1":
                proc.arguments = ["--aid=1", "--no-terminal", file]
            case "2":
                proc.arguments = ["--aid=2", "--no-terminal", file]
            default:
                // Mix both tracks with volume normalization
                proc.arguments = ["--lavfi-complex=[aid1]volume=0.3[v1];[aid2]volume=1.0[v2];[v1][v2]amix[ao]", "--no-terminal", file]
            }
            fputs("Playing \(track == "both" ? "both tracks (system 30%, mic 100%)" : "track \(track)"): \(URL(fileURLWithPath: file).lastPathComponent)\n", stderr)
            try? proc.run()
            proc.waitUntilExit()

        case "delete":
            guard args.count > 1 else {
                fputs("Usage: charlie-widget record delete <recording-id>\n", stderr)
                exit(1)
            }
            let recordingId = args[1]
            let json = "{\"command\":\"record_delete\",\"recording_id\":\"\(recordingId)\"}\n"
            await sendAndExpectOK(json)

        case "rename":
            guard args.count > 2 else {
                fputs("Usage: charlie-widget record rename <recording-id> <name>\n", stderr)
                exit(1)
            }
            let recordingId = args[1]
            let name = args[2...].joined(separator: " ")
            let escapedName = name.replacingOccurrences(of: "\"", with: "\\\"")
            let json = "{\"command\":\"record_rename\",\"recording_id\":\"\(recordingId)\",\"name\":\"\(escapedName)\"}\n"
            await sendAndExpectOK(json)

        case "transcribe":
            guard args.count > 1 else {
                fputs("Usage: charlie-widget record transcribe <recording-id> [--lang zh|en|ja|...]\n", stderr)
                exit(1)
            }
            let recordingId = args[1]
            var lang = ""
            if args.count > 2, args[2] == "--lang", args.count > 3 {
                lang = ",\"language\":\"\(args[3])\""
            }
            fputs("Transcribing (this may take a while, downloading model on first run)...\n", stderr)
            let json = "{\"command\":\"record_transcribe\",\"recording_id\":\"\(recordingId)\"\(lang)}\n"
            await sendAndPrintResponse(json, timeout: 600)

        case "diarize":
            guard args.count > 1 else {
                fputs("Usage: charlie-widget record diarize <recording-id>\n", stderr)
                exit(1)
            }
            let recordingId = args[1]
            fputs("Diarizing (assigning speaker labels)...\n", stderr)
            let json = "{\"command\":\"record_diarize\",\"recording_id\":\"\(recordingId)\"}\n"
            await sendAndPrintResponse(json, timeout: 600)

        case "identify":
            guard args.count > 1 else {
                fputs("Usage: charlie-widget record identify <recording-id>\n", stderr)
                exit(1)
            }
            let recordingId = args[1]
            fputs("Identifying speakers and translating...\n", stderr)
            let json = "{\"command\":\"record_identify\",\"recording_id\":\"\(recordingId)\"}\n"
            await sendAndPrintResponse(json, timeout: 600)

        case "summary":
            var dateStr = ""
            if args.count > 1, args[1] == "--date", args.count > 2 {
                dateStr = args[2]
            }
            fputs("Generating daily summary...\n", stderr)
            let json = "{\"command\":\"record_summary\",\"date\":\"\(dateStr)\"}\n"
            await sendAndPrintResponse(json, timeout: 600)

        case "live-transcript":
            var tailClause = ""
            if let idx = args.firstIndex(of: "--tail"), idx + 1 < args.count,
               let tail = Int(args[idx + 1]), tail > 0 {
                tailClause = ",\"tail\":\(tail)"
            }
            let json = "{\"command\":\"record_live_transcript\"\(tailClause)}\n"
            await sendAndPrintResponse(json)

        case "live-summary":
            let json = "{\"command\":\"record_live_summary\"}\n"
            await sendAndPrintResponse(json)

        case "live-status":
            let json = "{\"command\":\"record_live_status\"}\n"
            await sendAndPrintResponse(json)

        case "pin":
            let action: String = {
                if args.count > 1 {
                    switch args[1] {
                    case "show", "on", "open": return "show"
                    case "hide", "off", "close": return "hide"
                    default: return "toggle"
                    }
                }
                return "toggle"
            }()
            let json = "{\"command\":\"record_pin\",\"action\":\"\(action)\"}\n"
            await sendAndPrintResponse(json)

        default:
            fputs("Unknown record action: \(action)\n", stderr)
            fputs("Usage: charlie-widget record <start|stop|status|list|transcribe|diarize|identify|summary>\n", stderr)
            exit(1)
        }
    }

    // MARK: - Voice subcommand

    private static func handleVoice(_ args: [String]) async {
        guard let action = args.first else {
            fputs("Usage: charlie-widget voice <start|stop|status>\n", stderr)
            exit(1)
        }

        switch action {
        case "start":
            let json = "{\"command\":\"voice_start\"}\n"
            let response = await sendMessage(json)
            if let response {
                if response.contains("\"ok\":true") || response.contains("\"ok\": true") {
                    print("Voice recording started (press Option+V or run 'voice stop' to finish)")
                } else {
                    fputs("Error: \(response)\n", stderr)
                    exit(1)
                }
            }

        case "stop":
            fputs("Stopping, transcribing and sending to iTerm...\n", stderr)
            let json = "{\"command\":\"voice_stop\"}\n"
            await sendAndPrintResponse(json, timeout: 600)

        case "status":
            await sendAndPrintResponse("{\"command\":\"voice_status\"}\n")

        default:
            fputs("Unknown voice action: \(action)\n", stderr)
            fputs("Usage: charlie-widget voice <start|stop|status>\n", stderr)
            exit(1)
        }
    }

    // MARK: - Bubble subcommand

    private static func handleBubble(_ args: [String]) async {
        guard let action = args.first else {
            fputs("Usage: charlie-widget bubble <on|off|status>\n", stderr)
            exit(1)
        }

        switch action {
        case "on":
            let json = "{\"command\":\"bubble_on\"}\n"
            await sendAndExpectOK(json)
            print("Bubble overlay enabled")
        case "off":
            let json = "{\"command\":\"bubble_off\"}\n"
            await sendAndExpectOK(json)
            print("Bubble overlay disabled")
        case "status":
            let json = "{\"command\":\"bubble_status\"}\n"
            await sendAndPrintResponse(json)
        default:
            fputs("Unknown bubble action: \(action)\n", stderr)
            fputs("Usage: charlie-widget bubble <on|off|status>\n", stderr)
            exit(1)
        }
    }

    // MARK: - Music subcommand

    private static func handleMusic(_ args: [String]) async {
        guard let action = args.first else {
            fputs("Usage: charlie-widget music <on|off|status>\n", stderr)
            exit(1)
        }

        switch action {
        case "on":
            let json = "{\"command\":\"music_on\"}\n"
            await sendAndExpectOK(json)
            print("Music enabled")
        case "off":
            let json = "{\"command\":\"music_off\"}\n"
            await sendAndExpectOK(json)
            print("Music disabled")
        case "status":
            let json = "{\"command\":\"music_status\"}\n"
            await sendAndPrintResponse(json)
        default:
            fputs("Unknown music action: \(action)\n", stderr)
            fputs("Usage: charlie-widget music <on|off|status>\n", stderr)
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

    private static func sendAndPrintResponse(_ message: String, timeout: TimeInterval = 5) async {
        let response = await sendMessage(message, timeout: timeout)
        if let response {
            print(response)
        }
    }

    private static func sendMessage(_ message: String, timeout: TimeInterval = 5) async -> String? {
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

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
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
          charlie-widget record start          Start recording (both system + mic)
          charlie-widget record start --mic    Mic only
          charlie-widget record start --system System audio only
          charlie-widget record stop           Stop recording
          charlie-widget record status         Current recording state
          charlie-widget record list           List today's recordings
          charlie-widget record play           Play latest (both tracks mixed)
          charlie-widget record play --mic     Play mic track only
          charlie-widget record play --system  Play system track only
          charlie-widget record play <id>      Play specific recording
          charlie-widget record delete <id>       Delete a recording and all its files
          charlie-widget record rename <id> <name> Rename a recording
          charlie-widget record transcribe <id>  Transcribe a recording
          charlie-widget record diarize <id>    Assign speaker labels
          charlie-widget record identify <id>   Voice identification + translation
          charlie-widget record summary         Generate today's daily summary
          charlie-widget record summary --date YYYY-MM-DD
          charlie-widget record live-transcript       Current live transcription segments (JSON)
          charlie-widget record live-transcript --tail 20  Last N segments only
          charlie-widget record live-summary          Current rolling summary (JSON)
          charlie-widget record live-status           Live state (flags + counts)
          charlie-widget record pin [show|hide|toggle]  Toggle pinned floating transcript window
          charlie-widget bubble on             Enable bubble screensaver overlay
          charlie-widget bubble off            Disable bubble screensaver overlay
          charlie-widget bubble status         Show bubble overlay status
          charlie-widget music on              Enable session music cues
          charlie-widget music off             Disable session music cues
          charlie-widget music status          Show music status and script path
          charlie-widget voice start           Start voice command recording
          charlie-widget voice stop            Stop, transcribe, send to iTerm
          charlie-widget voice status          Current voice command state
        """
        fputs(usage + "\n", stderr)
    }
}
