import Foundation

// MARK: - Stream-JSON Codable types

/// Minimal envelope for every line in `--output-format stream-json`.
private struct StreamEvent: Decodable {
    let type: String
}

/// The `"result"` event that carries the final answer.
private struct ResultEvent: Decodable {
    let type: String
    let result: ResultContent
}

private struct ResultContent: Decodable {
    let text: String?
}

// MARK: - ClaudeClient

/// Runs Claude Code (`claude --bare -p …`) as a subprocess and returns the
/// final result text.
actor ClaudeClient {

    /// Absolute path to the `claude` binary.
    let claudePath: String

    /// Maximum wall-clock time before the subprocess is killed.
    let timeout: TimeInterval

    /// Permitted tools forwarded to `--allowed-tools`.
    let allowedTools: String

    // MARK: - Errors

    enum Error: Swift.Error, CustomStringConvertible {
        case processFailure(exitCode: Int32, stderr: String)
        case noResultEvent
        case timedOut

        var description: String {
            switch self {
            case .processFailure(let code, let stderr):
                return "claude exited with code \(code): \(stderr)"
            case .noResultEvent:
                return "No result event found in claude stream-json output"
            case .timedOut:
                return "claude subprocess timed out"
            }
        }
    }

    // MARK: - Init

    init(
        claudePath: String? = nil,
        timeout: TimeInterval = 60,
        allowedTools: String = "WebFetch,WebSearch"
    ) {
        self.claudePath = claudePath ?? ClaudeClient.defaultClaudePath()
        self.timeout = timeout
        self.allowedTools = allowedTools
    }

    // MARK: - Public API

    /// Send a prompt to Claude Code and return the final result text.
    func ask(_ prompt: String) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.arguments = [
            "--bare",
            "-p", prompt,
            "--output-format", "text",
            "--allowed-tools", allowedTools,
        ]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        let resultText: String = try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(self.timeout * 1_000_000_000))
                process.terminate()
                throw Error.timedOut
            }

            let value = try await group.next()!
            group.cancelAll()
            return value
        }

        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrString = String(data: stderrData, encoding: .utf8) ?? ""
            throw Error.processFailure(exitCode: process.terminationStatus, stderr: stderrString)
        }

        if resultText.isEmpty {
            throw Error.noResultEvent
        }
        return resultText
    }

    // MARK: - Private helpers

    /// Read stdout line by line and return the text from the first `"result"` event.
    private func parseStream(from handle: FileHandle) async throws -> String? {
        let decoder = JSONDecoder()
        var resultText: String?

        // Read all available data then split by newlines.
        // FileHandle.availableData blocks until data arrives or EOF.
        var buffer = Data()
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { break }          // EOF
            buffer.append(chunk)

            // Process complete lines
            while let range = buffer.range(of: Data("\n".utf8)) {
                let lineData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
                buffer.removeSubrange(buffer.startIndex...range.lowerBound)

                guard !lineData.isEmpty else { continue }

                // Quick check: is this a "result" event?
                if let envelope = try? decoder.decode(StreamEvent.self, from: lineData),
                   envelope.type == "result",
                   let event = try? decoder.decode(ResultEvent.self, from: lineData) {
                    resultText = event.result.text
                }
            }
        }

        // Handle any trailing data without a final newline
        if !buffer.isEmpty,
           let envelope = try? decoder.decode(StreamEvent.self, from: buffer),
           envelope.type == "result",
           let event = try? decoder.decode(ResultEvent.self, from: buffer) {
            resultText = event.result.text
        }

        return resultText
    }

    /// Best-effort resolution of the `claude` binary path.
    private static func defaultClaudePath() -> String {
        // Try common locations.
        let candidates = [
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin/claude",
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return candidates[0]
    }
}
