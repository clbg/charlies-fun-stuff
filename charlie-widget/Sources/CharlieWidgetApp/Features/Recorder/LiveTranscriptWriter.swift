import Foundation

/// Append-only JSONL writer for live transcript segments.
///
/// Each committed segment is written as a single JSON line to
/// `{stem}.transcript.partial`. On normal recording stop, the file is
/// promoted to `{stem}.transcript` (pretty JSON, matches offline schema)
/// and the partial is deleted. On crash, orphan partials are promoted on
/// app launch via `scanAndPromoteOrphans`.
@MainActor
final class LiveTranscriptWriter {

    private let partialURL: URL
    private let finalURL: URL
    private var fileHandle: FileHandle?
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()
    private var writeCount = 0

    init(partialURL: URL, finalURL: URL) throws {
        self.partialURL = partialURL
        self.finalURL = finalURL

        // Start fresh — old partial from a previous attempt (same second) should not be
        // concatenated onto. In practice filenames are second-precision so this is rare.
        try? FileManager.default.removeItem(at: partialURL)
        FileManager.default.createFile(atPath: partialURL.path, contents: nil)
        fileHandle = try FileHandle(forWritingTo: partialURL)
    }

    /// Append a segment as one JSONL line. Safe to call many times.
    func append(_ segment: TranscriptSegment) {
        guard let handle = fileHandle else { return }
        do {
            var data = try encoder.encode(segment)
            data.append(0x0A)  // '\n'
            try handle.write(contentsOf: data)
            writeCount += 1
            // fsync every 10 writes so crashes lose at most ~50s of transcription
            if writeCount % 10 == 0 {
                try handle.synchronize()
            }
        } catch {
            NSLog("[LiveTranscriptWriter] append failed: \(error)")
        }
    }

    /// Atomically promote the partial to the final transcript file.
    /// Re-encodes as pretty JSON matching the offline `.transcript` schema.
    func finalize() {
        close()
        do {
            let segments = try Self.readSegments(from: partialURL)
            let transcript = Transcript(segments: segments)
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try enc.encode(transcript)
            try data.write(to: finalURL, options: .atomic)
            try? FileManager.default.removeItem(at: partialURL)
        } catch {
            NSLog("[LiveTranscriptWriter] finalize failed: \(error)")
        }
    }

    func close() {
        try? fileHandle?.synchronize()
        try? fileHandle?.close()
        fileHandle = nil
    }

    // MARK: - Orphan Recovery

    /// Promote every orphan `.transcript.partial` found under `baseDir` (recursive into
    /// day subfolders). An orphan is a partial whose matching `.transcript` does not exist.
    /// Returns the number of partials promoted.
    @discardableResult
    static func scanAndPromoteOrphans(in baseDir: URL) -> Int {
        let fm = FileManager.default
        guard let dayDirs = try? fm.contentsOfDirectory(at: baseDir, includingPropertiesForKeys: nil) else {
            return 0
        }
        var promoted = 0
        for dayDir in dayDirs where (try? dayDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            guard let files = try? fm.contentsOfDirectory(at: dayDir, includingPropertiesForKeys: nil) else { continue }
            for file in files where file.lastPathComponent.hasSuffix(".transcript.partial") {
                // final path = strip ".partial" suffix
                let finalPath = file.deletingPathExtension()  // strips ".partial"
                // Skip if final already exists and is valid
                if fm.fileExists(atPath: finalPath.path),
                   let data = try? Data(contentsOf: finalPath),
                   (try? JSONDecoder().decode(Transcript.self, from: data)) != nil {
                    try? fm.removeItem(at: file)
                    continue
                }
                do {
                    let segments = try readSegments(from: file)
                    let transcript = Transcript(segments: segments)
                    let enc = JSONEncoder()
                    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let data = try enc.encode(transcript)
                    try data.write(to: finalPath, options: .atomic)
                    try? fm.removeItem(at: file)
                    promoted += 1
                    NSLog("[LiveTranscriptWriter] promoted orphan \(file.lastPathComponent) (\(segments.count) segments)")
                } catch {
                    NSLog("[LiveTranscriptWriter] failed to promote \(file.lastPathComponent): \(error)")
                }
            }
        }
        return promoted
    }

    /// Read JSONL segments. Drops (and logs) any malformed lines (e.g. last line
    /// truncated by a crash mid-write).
    private static func readSegments(from url: URL) throws -> [TranscriptSegment] {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        var segments: [TranscriptSegment] = []
        var dropped = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let lineData = line.data(using: .utf8) else { continue }
            if let seg = try? decoder.decode(TranscriptSegment.self, from: lineData) {
                segments.append(seg)
            } else {
                dropped += 1
            }
        }
        if dropped > 0 {
            NSLog("[LiveTranscriptWriter] dropped \(dropped) malformed JSONL line(s) in \(url.lastPathComponent)")
        }
        return segments
    }
}
