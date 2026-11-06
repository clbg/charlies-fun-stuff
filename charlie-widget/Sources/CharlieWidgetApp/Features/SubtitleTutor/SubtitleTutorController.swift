import AppKit
import CharlieLLM
import Observation
import ScreenCaptureKit
import UniformTypeIdentifiers

/// Subtitle Tutor: watches a screen region (e.g. YouTube subtitles), OCRs the Japanese line, and streams a
/// Chinese translation + grammar notes into a panel right above the subtitle.
///
///   capture (ScreenCaptureKit, every 200ms) → Vision OCR (~40-90ms) → text changed?
///     → cache hit: show instantly · else stream from the configured model (CharlieLLM)
///     → OCR unsure (low confidence twice): send the frame image to the model instead
@MainActor
@Observable
final class SubtitleTutorController {
    private(set) var isRunning = false
    private(set) var region: CGRect? = SubtitleStorage.region
    private(set) var lastLatencyMs: Int?
    private(set) var cacheCount = 0
    private(set) var lastError: String?

    @ObservationIgnored private let llm: LLMSettingsStore
    @ObservationIgnored private var provider: any LLMProvider
    @ObservationIgnored private var overlay: SubtitleOverlayPanel?
    @ObservationIgnored private lazy var cache = ExplanationCache()
    @ObservationIgnored private var log: SubtitleEventLog?
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var tracker = SubtitleTracker()
    @ObservationIgnored private let picker = SubtitleRegionPicker()
    @ObservationIgnored private var inflight: [Int: Task<Void, Never>] = [:]
    @ObservationIgnored private var requests: [Int: Request] = [:]
    @ObservationIgnored private var currentRequest: Int?
    @ObservationIgnored private var lastSubtitle: String?
    @ObservationIgnored private var nextId = 1
    @ObservationIgnored var intervalMs = 200

    private struct Request {
        let subtitle: String?        // nil until an image read reports it
        let captureStart: Double
        let ocrMs: Double
        let isImage: Bool
        var firstMs: Double?
        var streamed = ""
        var imageLineDone = false    // image mode: "字幕：…" first line already parsed
    }

    init(llm: LLMSettingsStore) {
        self.llm = llm
        provider = LLM.provider(for: llm.config)
    }

    // MARK: - Control

    /// Starts watching `region` (or the saved one; with neither, asks the user to draw it).
    func start(region newRegion: CGRect? = nil, duration: Double? = nil) {
        if let newRegion { setRegion(newRegion) }
        guard let region else { pickRegion(); return }
        stopLoop()
        provider = LLM.provider(for: llm.config)   // pick up settings changes
        tracker = SubtitleTracker()
        lastError = nil
        cacheCount = cache.count
        let log = SubtitleEventLog()
        self.log = log
        log.log("start", ["interval_ms": intervalMs, "model": llm.config.model, "provider": llm.config.kind.rawValue,
                          "cache_entries": cache.count, "log": log.path])
        log.log("region", ["x": region.minX, "y": region.minY, "w": region.width, "h": region.height])

        if overlay == nil {
            let o = SubtitleOverlayPanel(band: region)
            o.onClose = { [weak self] in self?.stop() }
            o.onPickRegion = { [weak self] in self?.pickRegion() }
            overlay = o
        } else {
            overlay?.setBand(region)
        }
        overlay?.show()
        isRunning = true

        let provider = self.provider
        Task.detached(priority: .utility) { SubtitleOCR.warm() }
        Task { [weak self] in
            await provider.warmUp()
            self?.log?.log("llm_warm")
        }
        loop = Task { [weak self] in await self?.runLoop() }
        if let duration {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(duration))
                self?.log?.log("quit")
                self?.stop()
            }
        }
    }

    func stop() {
        stopLoop()
        inflight.values.forEach { $0.cancel() }
        inflight = [:]
        requests = [:]
        overlay?.close()
        overlay = nil
        log?.close()
        isRunning = false
    }

    func toggle() { isRunning ? stop() : start() }

    func pickRegion() {
        picker.pick { [weak self] r in self?.start(region: r) }
    }

    func resetPanel() {
        if let overlay { overlay.resetPlacement() } else { SubtitleStorage.panelPlacement = nil }
    }

    func clearCache() {
        cache.clear()
        cacheCount = 0
    }

    func statusJSON() -> String {
        var obj: [String: Any] = ["running": isRunning, "cache_entries": cache.count,
                                  "model": llm.config.model, "provider": llm.config.kind.rawValue]
        if let r = region { obj["region"] = [r.minX, r.minY, r.width, r.height] }
        if let l = lastLatencyMs { obj["last_latency_ms"] = l }
        if let e = lastError { obj["last_error"] = e }
        if let p = log?.path { obj["log"] = p }
        let d = (try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])) ?? Data("{}".utf8)
        return String(decoding: d, as: UTF8.self)
    }

    private func setRegion(_ r: CGRect) {
        if r != region { SubtitleStorage.panelPlacement = nil; display = nil }   // new band: default panel placement again
        region = r
        SubtitleStorage.region = r
    }

    private func stopLoop() {
        loop?.cancel()
        loop = nil
    }

    // MARK: - Capture loop

    private struct Frame: @unchecked Sendable { let image: CGImage }   // CGImage is immutable

    private func runLoop() async {
        while !Task.isCancelled, isRunning {
            let start = SubtitleClock.nowMs()
            if let region {
                do {
                    let frame = Frame(image: try await capture(region))
                    let capMs = SubtitleClock.nowMs() - start
                    let result = await Task.detached(priority: .userInitiated) { SubtitleOCR.recognize(frame.image) }.value
                    if Task.isCancelled { return }
                    onFrame(frame.image, result, start: start, capMs: capMs)
                } catch {
                    log?.log("capture_error", ["message": "\(error)"])
                    lastError = "Screen capture failed: \(error.localizedDescription)"
                }
            }
            let wait = Double(intervalMs) - (SubtitleClock.nowMs() - start)
            try? await Task.sleep(for: .milliseconds(max(10, wait)))
        }
    }

    @ObservationIgnored private var display: (SCDisplay, CGRect)?   // display containing the region + its frame

    /// Region screenshot via the macOS 14 API (captureImage(in:) needs 15.2): filter = the display that
    /// contains the region, sourceRect = region relative to that display, at native pixel scale.
    private func capture(_ region: CGRect) async throws -> CGImage {
        if display == nil || !(display!.1.contains(region.origin)) {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let d = content.displays.first(where: { $0.frame.contains(region.origin) }) ?? content.displays.first else {
                throw NSError(domain: "SubtitleTutor", code: 1, userInfo: [NSLocalizedDescriptionKey: "no display"])
            }
            display = (d, d.frame)
        }
        let (d, frame) = display!
        let scale = NSScreen.screens.first { ScreenCoords.fromAppKit($0.frame).contains(region.origin) }?.backingScaleFactor ?? 2
        let config = SCStreamConfiguration()
        config.sourceRect = CGRect(x: region.minX - frame.minX, y: region.minY - frame.minY,
                                   width: region.width, height: region.height)
        config.width = Int(region.width * scale)
        config.height = Int(region.height * scale)
        config.showsCursor = false
        return try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(display: d, excludingWindows: []),
                                                          configuration: config)
    }

    private func onFrame(_ img: CGImage, _ r: OCRResult, start: Double, capMs: Double) {
        if !r.text.isEmpty {
            log?.log("ocr", ["text": r.text, "conf": Double(r.confidence), "ocr_ms": r.ms.rounded(), "cap_ms": capMs.rounded()])
        }
        switch tracker.feed(r) {
        case .none:
            return
        case .newText(let t):
            send(text: t, frame: img, start: start, ocrMs: r.ms, replacing: nil)
        case .updateText(let t):
            send(text: t, frame: img, start: start, ocrMs: r.ms, replacing: currentRequest)
        case .needVision:
            log?.log("need_vision", ["text": r.text, "conf": Double(r.confidence)])
            send(text: nil, frame: img, start: start, ocrMs: r.ms, replacing: nil)
        }
    }

    // MARK: - Requests

    /// text == nil: send the frame image to the model instead of OCR text.
    private func send(text: String?, frame: CGImage, start: Double, ocrMs: Double, replacing: Int?) {
        if let replacing { inflight.removeValue(forKey: replacing)?.cancel(); requests.removeValue(forKey: replacing) }
        let id = nextId; nextId += 1
        currentRequest = id

        if let text, let hit = cache.lookup(text) {
            overlay?.begin(id: id, subtitle: text, imageRead: false)
            overlay?.append(id: id, hit.explanation)
            overlay?.finish(id: id, status: "缓存 · OCR \(Int(ocrMs))ms")
            lastSubtitle = text
            let ms = (SubtitleClock.nowMs() - start).rounded()
            lastLatencyMs = Int(ms)
            log?.log("emit", ["id": id, "text": text, "source": "cache", "replacing": replacing ?? 0, "ocr_ms": ocrMs.rounded()])
            log?.log("first_display", ["id": id, "latency_ms": ms])
            log?.log("cache_hit", ["id": id, "text": text, "cached": hit.subtitle, "latency_ms": ms])
            return
        }

        let context = lastSubtitle.map { "【上一句，仅供理解语境，不要翻译或讲解它】\($0)\n" } ?? ""
        let content: [LLMContent]
        if let text {
            content = [.text(context + "【要讲解的字幕】" + text)]
            lastSubtitle = text
        } else {
            guard let png = Self.pngData(frame) else { return }
            content = [.imagePNG(png), .text(context + SubtitlePrompts.imageInstruction)]
        }
        requests[id] = Request(subtitle: text, captureStart: start, ocrMs: ocrMs, isImage: text == nil)
        overlay?.begin(id: id, subtitle: text ?? "（识别中…）", imageRead: text == nil)
        log?.log("emit", ["id": id, "text": text ?? "", "source": text == nil ? "vision" : "ocr",
                          "replacing": replacing ?? 0, "ocr_ms": ocrMs.rounded()])

        let request = LLMRequest(system: SubtitlePrompts.system,
                                 messages: [LLMMessage(role: "user", content: content)], maxTokens: 600)
        let provider = self.provider
        inflight[id] = Task { [weak self] in
            do {
                for try await event in provider.stream(request) {
                    guard let self, !Task.isCancelled else { return }
                    self.handle(id, event)
                }
            } catch is CancellationError {
            } catch {
                self?.fail(id, error)
            }
        }
    }

    private func handle(_ id: Int, _ event: LLMEvent) {
        guard var req = requests[id] else { return }
        switch event {
        case .text(var piece):
            if req.firstMs == nil {
                req.firstMs = SubtitleClock.nowMs()
                let ms = (req.firstMs! - req.captureStart).rounded()
                lastLatencyMs = Int(ms)
                log?.log("first_display", ["id": id, "latency_ms": ms])
            }
            if req.isImage && !req.imageLineDone {
                // Hold text back until the "字幕：…" line is complete, then show it as the subtitle.
                req.streamed += piece
                guard let nl = req.streamed.firstIndex(of: "\n") else { requests[id] = req; return }
                let line = String(req.streamed[..<nl])
                piece = String(req.streamed[req.streamed.index(after: nl)...]).trimmingCharacters(in: .newlines)
                req.streamed = ""
                req.imageLineDone = true
                let read = line.replacingOccurrences(of: "字幕：", with: "").trimmingCharacters(in: .whitespaces)
                guard line.hasPrefix("字幕："), !read.isEmpty, read != "（无）" else {
                    // No subtitle in the picture, or the model ignored the format.
                    inflight.removeValue(forKey: id)?.cancel()
                    requests.removeValue(forKey: id)
                    overlay?.clear(id: id)
                    log?.log("vision_read", ["id": id, "text": "", "raw": line])
                    return
                }
                req = Request(subtitle: read, captureStart: req.captureStart, ocrMs: req.ocrMs, isImage: true,
                              firstMs: req.firstMs, streamed: "", imageLineDone: true)
                tracker.adoptVisionRead(read)
                lastSubtitle = read
                overlay?.setSubtitle(id: id, read)
                log?.log("vision_read", ["id": id, "text": read])
            }
            req.streamed += piece
            requests[id] = req
            overlay?.append(id: id, piece)
        case .done(let ttftMs, _):
            requests.removeValue(forKey: id)
            inflight.removeValue(forKey: id)
            let now = SubtitleClock.nowMs()
            let firstMs = (req.firstMs ?? now) - req.captureStart
            let totalMs = now - req.captureStart
            overlay?.finish(id: id, status: String(format: "OCR %.0fms · 首字 %.2fs · 完成 %.1fs",
                                                   req.ocrMs, firstMs / 1000, totalMs / 1000))
            let explanation = req.streamed.trimmingCharacters(in: .whitespacesAndNewlines)
            if let subtitle = req.subtitle {
                cache.store(subtitle: subtitle, explanation: explanation, model: llm.config.model)
                cacheCount = cache.count
            }
            log?.log("done", ["id": id, "first_ms": firstMs.rounded(), "total_ms": totalMs.rounded(),
                              "llm_ttft_ms": ttftMs, "explanation": explanation])
        }
    }

    private func fail(_ id: Int, _ error: Error) {
        requests.removeValue(forKey: id)
        inflight.removeValue(forKey: id)
        let message = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        lastError = message
        overlay?.finish(id: id, status: "出错：\(message)")
        log?.log("llm_error", ["id": id, "message": message])
    }

    private static func pngData(_ img: CGImage) -> Data? {
        let d = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(d, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, img, nil)
        return CGImageDestinationFinalize(dest) ? d as Data : nil
    }
}

enum SubtitlePrompts {
    static let system = """
    你是日语老师，帮中文母语的学习者看懂视频里的日语字幕。
    输出格式固定，简短，不要寒暄：
    译：<自然的中文翻译>
    · <语法点或惯用表达>：<一句话解释>
    · ……（最多 3 条，挑对理解这句最关键的；简单句可以只写 1 条）
    解释必须准确：拿不准的语法点就不要写。不用 markdown 标题。
    """

    static let imageInstruction = """
    图片是视频画面里的字幕区域。第一行必须是「字幕：」开头，不要描述图片。先读出其中的日语字幕，单独一行写成：
    字幕：<原文>
    然后按固定格式讲解。如果图片里没有日语字幕，只输出：字幕：（无）
    """
}
