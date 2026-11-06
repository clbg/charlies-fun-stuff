import CoreGraphics
import Foundation
@preconcurrency import Vision

struct OCRResult: Sendable {
    let text: String         // kept lines joined with "\n", top to bottom
    let confidence: Float    // mean confidence of kept lines (0 if none)
    let ms: Double
}

enum SubtitleOCR {
    /// Vision `.accurate` is required: `.fast` has no Japanese model and returns garbage.
    nonisolated static func recognize(_ image: CGImage) -> OCRResult {
        let t0 = SubtitleClock.nowMs()
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.recognitionLanguages = ["ja-JP", "en-US"]
        req.usesLanguageCorrection = true
        try? VNImageRequestHandler(cgImage: image).perform([req])
        let obs = (req.results ?? [])
            .compactMap { o -> (CGFloat, CGFloat, VNRecognizedText)? in
                guard let c = o.topCandidates(1).first else { return nil }
                return (o.boundingBox.midY, o.boundingBox.minX, c)
            }
            // Vision boxes are bottom-left origin: higher midY = higher on screen.
            .sorted { abs($0.0 - $1.0) > 0.05 ? $0.0 > $1.0 : $0.1 < $1.1 }
        // Drop lines that aren't Japanese dialogue: player timestamps ("0:06 / 7:21"), logos, English UI,
        // and kanji-only lines (usually Chinese UI text) — a Japanese subtitle line has at least one kana.
        let kept = obs.filter { o in
            let n = SubtitleText.normalize(o.2.string)
            let jp = SubtitleText.japaneseCount(n)
            return jp >= 2 && Double(jp) / Double(max(n.count, 1)) >= 0.3 && SubtitleText.kanaCount(n) >= 1
        }
        let conf = kept.isEmpty ? 0 : kept.map { $0.2.confidence }.reduce(0, +) / Float(kept.count)
        return OCRResult(text: kept.map { $0.2.string }.joined(separator: "\n"), confidence: conf,
                         ms: SubtitleClock.nowMs() - t0)
    }

    /// The first Vision request loads the model (~200-400ms); do it once at start.
    nonisolated static func warm() {
        guard let ctx = CGContext(data: nil, width: 64, height: 16, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0),
              let img = ctx.makeImage() else { return }
        _ = recognize(img)
    }
}

enum SubtitleClock {
    /// Monotonic milliseconds, for latency measurement.
    nonisolated static func nowMs() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000 }
}

enum SubtitleText {
    /// NFKC + no whitespace, so width variants and line breaks don't count as text changes.
    nonisolated static func normalize(_ s: String) -> String {
        String(String.UnicodeScalarView(s.precomposedStringWithCompatibilityMapping.unicodeScalars
            .filter { !CharacterSet.whitespacesAndNewlines.contains($0) }))
    }

    nonisolated static func japaneseCount(_ s: String) -> Int {
        s.unicodeScalars.filter {
            (0x3040...0x30FF).contains($0.value) || (0x4E00...0x9FFF).contains($0.value)
                || (0x3400...0x4DBF).contains($0.value)
        }.count
    }

    nonisolated static func kanaCount(_ s: String) -> Int {
        s.unicodeScalars.filter { (0x3040...0x30FF).contains($0.value) }.count
    }

    /// Levenshtein similarity in [0, 1].
    nonisolated static func similarity(_ a: String, _ b: String) -> Double {
        let x = Array(a), y = Array(b)
        if x.isEmpty && y.isEmpty { return 1 }
        if x.isEmpty || y.isEmpty { return 0 }
        var prev = Array(0...y.count), cur = [Int](repeating: 0, count: y.count + 1)
        for i in 1...x.count {
            cur[0] = i
            for j in 1...y.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1))
            }
            swap(&prev, &cur)
        }
        return 1 - Double(prev[y.count]) / Double(max(x.count, y.count))
    }
}

/// Decides, frame by frame, when a *new* subtitle has appeared.
/// Change detection is on recognised text, not pixels: the video behind the subtitle moves every frame.
struct SubtitleTracker {
    enum Action: Equatable {
        case none
        case newText(String)      // send OCR text to the model
        case updateText(String)   // same cue, better read (first frame caught a fade-in): resend
        case needVision           // OCR can't read it confidently: send the image instead
    }

    let minConfidence: Float
    private var current: String?   // normalized text of the cue on screen
    private var updatedOnce = false
    private var emptyFrames = 0
    private var badFrames = 0
    private var visionSentForBad = false

    init(minConfidence: Float = 0.5) { self.minConfidence = minConfidence }

    mutating func feed(_ r: OCRResult) -> Action {
        let norm = SubtitleText.normalize(r.text)
        if norm.isEmpty {
            emptyFrames += 1
            badFrames = 0
            if emptyFrames >= 2 { current = nil; visionSentForBad = false }
            return .none
        }
        emptyFrames = 0

        if r.confidence < minConfidence {
            // One bad frame is usually a fade transition; two in a row means OCR really can't read it.
            badFrames += 1
            if badFrames >= 2 && !visionSentForBad { visionSentForBad = true; return .needVision }
            return .none
        }
        badFrames = 0
        visionSentForBad = false

        if let cur = current {
            let sim = SubtitleText.similarity(norm, cur)
            if sim >= 0.98 { return .none }
            if sim >= 0.6 {
                // Same cue, slightly different read: accept only a longer read, at most once per cue.
                if norm.count > cur.count && !updatedOnce {
                    updatedOnce = true
                    current = norm
                    return .updateText(r.text)
                }
                return .none
            }
        }
        current = norm
        updatedOnce = false
        return .newText(r.text)
    }

    /// Image reads report the text the model saw, so later OCR frames of the same cue are deduped.
    mutating func adoptVisionRead(_ text: String) {
        let n = SubtitleText.normalize(text)
        if !n.isEmpty { current = n }
    }
}
