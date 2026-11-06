import AppKit
import Foundation

/// Everything Subtitle Tutor writes lives under ~/Library/Application Support/CharlieWidget/SubtitleTutor/
/// (override with CHARLIE_SUBTITLE_HOME for tests):
///   cache.jsonl     explanations keyed by subtitle text
///   logs/*.jsonl    one event log per run (scripts/subtitle-eval.py reads these)
/// Small settings (region, panel placement) live in UserDefaults like the rest of the app.
enum SubtitleStorage {
    nonisolated static var home: URL {
        if let p = ProcessInfo.processInfo.environment["CHARLIE_SUBTITLE_HOME"] { return URL(fileURLWithPath: p) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CharlieWidget/SubtitleTutor")
    }

    // UserDefaults keys
    private static let regionKey = "CharlieWidget.subtitle.region"   // [x, y, w, h], screen points, top-left origin
    private static let panelKey = "CharlieWidget.subtitle.panel"     // [x, y, w], AppKit coords

    static var region: CGRect? {
        get { rect(UserDefaults.standard.array(forKey: regionKey) as? [Double], count: 4) }
        set { UserDefaults.standard.set(newValue.map { [$0.minX, $0.minY, $0.width, $0.height] }, forKey: regionKey) }
    }

    static var panelPlacement: NSRect? {
        get { rect(UserDefaults.standard.array(forKey: panelKey) as? [Double], count: 3) }
        set { UserDefaults.standard.set(newValue.map { [$0.minX, $0.minY, $0.width] }, forKey: panelKey) }
    }

    private static func rect(_ a: [Double]?, count: Int) -> CGRect? {
        guard let a, a.count == count else { return nil }
        return CGRect(x: a[0], y: a[1], width: a[2], height: count == 4 ? a[3] : 0)
    }
}

/// Global display coords (top-left origin, used by ScreenCaptureKit) <-> AppKit (bottom-left origin).
enum ScreenCoords {
    static var mainHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }
    static func toAppKit(_ r: CGRect) -> NSRect {
        NSRect(x: r.minX, y: mainHeight - r.minY - r.height, width: r.width, height: r.height)
    }
    static func fromAppKit(_ r: NSRect) -> CGRect {
        CGRect(x: r.minX, y: mainHeight - r.minY - r.height, width: r.width, height: r.height)
    }
}

/// Explanations keyed by normalized subtitle text, persisted as JSONL, so seeking back / rewatching shows the
/// explanation instantly instead of calling the model again.
@MainActor
final class ExplanationCache {
    struct Item: Codable {
        let key: String
        let subtitle: String
        let explanation: String
        let model: String
        let at: Double
    }

    private var byKey: [String: Item] = [:]
    private var items: [Item] = []
    private let url = SubtitleStorage.home.appendingPathComponent("cache.jsonl")

    init() {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            for line in text.split(separator: "\n") {
                if let it = try? JSONDecoder().decode(Item.self, from: Data(line.utf8)) { byKey[it.key] = it }
            }
            items = Array(byKey.values)
        }
    }

    var count: Int { byKey.count }

    /// Exact normalized match first; otherwise the most similar cached line (OCR can differ by a character).
    func lookup(_ subtitle: String) -> Item? {
        let k = SubtitleText.normalize(subtitle)
        if let it = byKey[k] { return it }
        var best: (Double, Item)?
        for it in items where abs(it.key.count - k.count) <= max(2, k.count / 10) {
            let s = SubtitleText.similarity(it.key, k)
            if s >= 0.9, s > (best?.0 ?? 0) { best = (s, it) }
        }
        return best?.1
    }

    func store(subtitle: String, explanation: String, model: String) {
        let k = SubtitleText.normalize(subtitle)
        guard !k.isEmpty, !explanation.isEmpty else { return }
        let it = Item(key: k, subtitle: subtitle, explanation: explanation, model: model, at: Date().timeIntervalSince1970)
        if byKey[k] == nil { items.append(it) }
        byKey[k] = it
        guard let d = try? JSONEncoder().encode(it) else { return }
        let line = d + Data("\n".utf8)
        // Throwing FileHandle APIs only: the legacy write(_:)/seekToEndOfFile() raise ObjC exceptions, which
        // unwinding through Swift async code corrupts the concurrency runtime.
        if let h = try? FileHandle(forWritingTo: url) {
            _ = try? h.seekToEnd(); try? h.write(contentsOf: line); try? h.close()
        } else {
            try? line.write(to: url)
        }
    }

    func clear() {
        byKey = [:]; items = []
        try? FileManager.default.removeItem(at: url)
    }
}

/// JSONL event log, one file per run.
@MainActor
final class SubtitleEventLog {
    let path: String
    private let handle: FileHandle?
    private let t0 = SubtitleClock.nowMs()

    init() {
        let dir = SubtitleStorage.home.appendingPathComponent("logs").path
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"
        path = "\(dir)/session-\(f.string(from: Date())).jsonl"
        FileManager.default.createFile(atPath: path, contents: nil)
        handle = FileHandle(forWritingAtPath: path)
    }

    func log(_ ev: String, _ fields: [String: Any] = [:]) {
        var obj = fields
        obj["ev"] = ev
        obj["t_ms"] = (SubtitleClock.nowMs() - t0).rounded()
        obj["wall"] = Date().timeIntervalSince1970
        guard !closed, let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]) else { return }
        try? handle?.write(contentsOf: data + Data("\n".utf8))
    }

    /// Late events (warm-up finishing, the last frame) can arrive after stop(); they are dropped, not written to
    /// a closed handle (which raised an ObjC exception through Swift async code).
    func close() { closed = true; try? handle?.close() }
    private var closed = false
}
