import CharlieLLM
import Foundation

// Manual test + latency benchmark tool for CharlieLLM.
//
//   llm-smoke [--preset ID] [--model M] [--profile P] [--region R] [--base-url U] [--image file.png] [--max-tokens N] [--system TEXT] [--warmup] [--cancel-after-first] "prompt"
//   llm-smoke --bench [--presets id1,id2] [--n 6] [--max-tokens N]
//   llm-smoke --selftest
//   llm-smoke --list
//
// Set CHARLIE_LLM_DEBUG=1 for library debug logs on stderr (never includes secrets).

let usage = """
usage:
  llm-smoke [--preset ID] [--model M] [--profile P] [--region R] [--base-url U] [--image file.png] [--max-tokens N] [--system TEXT] [--warmup] [--cancel-after-first] "prompt"
  llm-smoke --bench [--presets id1,id2] [--n 6] [--max-tokens N]
  llm-smoke --selftest
  llm-smoke --list
"""

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write(Data("error: \(msg)\n".utf8))
    exit(1)
}

func out(_ s: String) {
    FileHandle.standardOutput.write(Data(s.utf8))
}

func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
func ms(_ from: UInt64, _ to: UInt64 = now()) -> Int { Int((to - from) / 1_000_000) }

// MARK: - Arg parsing

var args = Array(CommandLine.arguments.dropFirst())
var opts: [String: String] = [:]
var flags: Set<String> = []
var positional: [String] = []
let valued: Set<String> = ["--preset", "--image", "--max-tokens", "--system", "--presets", "--n",
                           "--model", "--profile", "--region", "--base-url"]
var i = 0
while i < args.count {
    let a = args[i]
    if valued.contains(a) {
        guard i + 1 < args.count else { fail("\(a) needs a value") }
        opts[a] = args[i + 1]; i += 2
    } else if a.hasPrefix("--") {
        flags.insert(a); i += 1
    } else {
        positional.append(a); i += 1
    }
}

if flags.contains("--help") || flags.contains("-h") { out(usage + "\n"); exit(0) }

func preset(_ id: String) -> LLMPreset {
    guard let p = LLMPresets.preset(id: id) else {
        fail("unknown preset '\(id)'. Known: \(LLMPresets.all.map(\.id).joined(separator: ", "))")
    }
    return p
}

// MARK: - Modes

if flags.contains("--list") {
    for p in LLMPresets.all {
        let c = p.config
        out("\(p.id.padding(toLength: 28, withPad: " ", startingAt: 0)) \(p.label) [\(p.note)]  kind=\(c.kind.rawValue) model=\(c.model) region=\(c.awsRegion) thinking=\(c.thinking ?? "-") effort=\(c.effort ?? "-")\n")
    }
    exit(0)
}

if flags.contains("--selftest") {
    let checks = LLMSelfTest.run()
    for c in checks { out("\(c.ok ? "PASS" : "FAIL")  \(c.name)\n      \(c.detail)\n") }
    let failed = checks.filter { !$0.ok }.count
    out("\n\(checks.count - failed)/\(checks.count) passed\n")
    exit(failed == 0 ? 0 : 1)
}

let maxTokens = Int(opts["--max-tokens"] ?? "") ?? 300

if flags.contains("--bench") {
    let ids = (opts["--presets"] ?? "bedrock-jp-haiku-4-5,bedrock-us-haiku-5-5,bedrock-us-sonnet-5-5,bedrock-global-sonnet-5-5")
        .split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
    let n = Int(opts["--n"] ?? "") ?? 6
    let system = "你是日语老师。用户给你一句日语字幕，用简短中文解释意思和关键语法，不超过三行。"
    let base = [
        "今日はちょっと寄り道してから帰ろうかな。",
        "そんなこと言われても、困るんだけど。",
        "まさか彼が来るとは思わなかった。",
        "せっかくだから、もう少しゆっくりしていけば？",
        "あの時ちゃんと謝っておけばよかったのに。",
        "雨が降りそうだから、傘を持っていったほうがいいよ。",
    ]
    let prompts = (0..<n).map { base[$0 % base.count] }
    var rows: [(LLMPreset, LLMBenchmark.Result)] = []
    for id in ids {
        let p = preset(id)
        out("benchmarking \(id) (\(n) prompts, max_tokens \(maxTokens))…\n")
        let r = await LLMBenchmark.measure(p.config, system: system, prompts: prompts, maxTokens: maxTokens)
        rows.append((p, r))
    }
    out("\npreset                        median_ttft  samples (ms)                          error\n")
    for (p, r) in rows {
        let med = r.medianTTFTMs.map { "\($0) ms" } ?? "-"
        out("\(p.id.padding(toLength: 30, withPad: " ", startingAt: 0))\(med.padding(toLength: 13, withPad: " ", startingAt: 0))\(r.ttftMs.map(String.init).joined(separator: ",").padding(toLength: 38, withPad: " ", startingAt: 0))\(r.error ?? "")\n")
    }
    exit(0)
}

// Single prompt.
guard let prompt = positional.first else { fail("missing prompt\n\(usage)") }
var p = preset(opts["--preset"] ?? "bedrock-us-sonnet-5-5")
if opts["--model"] != nil || opts["--profile"] != nil || opts["--region"] != nil || opts["--base-url"] != nil {
    var c = p.config
    if let v = opts["--model"] { c.model = v }
    if let v = opts["--profile"] { c.awsProfile = v }
    if let v = opts["--region"] { c.awsRegion = v }
    if let v = opts["--base-url"] { c.baseURL = v }
    p = LLMPreset(id: p.id + "+override", label: p.label, note: p.note, config: c)
}
var content: [LLMContent] = []
if let path = opts["--image"] {
    guard let data = FileManager.default.contents(atPath: path) else { fail("cannot read image \(path)") }
    content.append(.imagePNG(data))
}
content.append(.text(prompt))
let request = LLMRequest(system: opts["--system"] ?? "", messages: [LLMMessage(role: "user", content: content)], maxTokens: maxTokens)
let provider = LLM.provider(for: p.config)

out("[preset \(p.id): \(p.config.model) @ \(p.config.kind == .bedrock ? p.config.awsRegion : p.config.baseURL)]\n")

if flags.contains("--warmup") {
    let t = now()
    await provider.warmUp()
    out("[warmUp \(ms(t)) ms]\n")
}

if flags.contains("--cancel-after-first") {
    // Cancel the consuming Task right after the first token and time how fast the stream winds down.
    final class Box: @unchecked Sendable { var firstAt: UInt64?; var chunksAfterCancel = 0; var cancelled = false }
    let box = Box()
    let start = now()
    let consumer = Task {
        do {
            for try await ev in provider.stream(request) {
                switch ev {
                case .text(let t):
                    if box.cancelled { box.chunksAfterCancel += 1; continue }
                    out(t)
                    box.firstAt = now()
                    box.cancelled = true
                    withUnsafeCurrentTask { $0?.cancel() }
                case .done(let ttft, let total):
                    out("\n[done ttft=\(ttft)ms total=\(total)ms — stream was NOT cancelled]\n")
                }
            }
            return "stream ended (nil)"
        } catch {
            return "stream threw \(type(of: error))"
        }
    }
    let how = await consumer.value
    let end = now()
    if let f = box.firstAt {
        out("\n[first token at \(ms(start, f)) ms; cancelled; consumer loop exited \(ms(f, end)) ms later via: \(how); text events after cancel: \(box.chunksAfterCancel)]\n")
    } else {
        out("\n[no token received: \(how)]\n")
    }
    // Give the library's producer task a moment to log its cancellation (visible with CHARLIE_LLM_DEBUG=1).
    try? await Task.sleep(nanoseconds: 300_000_000)
    exit(0)
}

do {
    for try await ev in provider.stream(request) {
        switch ev {
        case .text(let t): out(t)
        case .done(let ttft, let total): out("\n[ttft=\(ttft)ms total=\(total)ms]\n")
        }
    }
} catch {
    fail(error.localizedDescription)
}
