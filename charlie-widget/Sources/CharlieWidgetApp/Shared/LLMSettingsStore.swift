import CharlieLLM
import Foundation
import Observation

/// The app-wide model configuration (one place for every feature that calls a model).
/// Config is stored in UserDefaults; API keys live in the Keychain (LLMKeychain), never in defaults.
@MainActor
@Observable
final class LLMSettingsStore {
    private static let configKey = "CharlieWidget.llm.config"

    var config: LLMConfig {
        didSet { if config != oldValue { save(); benchmark = nil } }
    }

    /// Last "测速" result for the current config, shown in Settings.
    private(set) var benchmark: String?
    private(set) var isBenchmarking = false

    init() {
        if let d = UserDefaults.standard.data(forKey: Self.configKey),
           let c = try? JSONDecoder().decode(LLMConfig.self, from: d) {
            config = c
        } else {
            config = .default
        }
    }

    var presets: [LLMPreset] { LLMPresets.all }

    /// Preset whose config equals the current one (nil = customised).
    var matchingPresetId: String? { presets.first { $0.config == config }?.id }

    func apply(_ preset: LLMPreset) { config = preset.config }

    var needsAPIKey: Bool { config.kind != .bedrock }

    var apiKey: String {
        get { LLMKeychain.apiKey(for: config.kind) ?? "" }
        set { LLMKeychain.setAPIKey(newValue.isEmpty ? nil : newValue, for: config.kind) }
    }

    /// Measures time-to-first-token for the current config with three short subtitle prompts.
    func runBenchmark() {
        guard !isBenchmarking else { return }
        isBenchmarking = true
        benchmark = "测速中…"
        let config = self.config
        Task {
            let r = await LLMBenchmark.measure(
                config, system: SubtitlePrompts.system,
                prompts: ["【要讲解的字幕】もう二度と会えないかもしれないけど、忘れないでね。",
                          "【要讲解的字幕】そんなに急がなくてもいいじゃない。",
                          "【要讲解的字幕】行けば行くほど、道が分からなくなる。"],
                maxTokens: 300)
            if config == self.config {
                if let e = r.error {
                    benchmark = "失败：\(e)"
                } else if let m = r.medianTTFTMs {
                    benchmark = "首字中位数 \(m) ms（\(r.ttftMs.map(String.init).joined(separator: " / ")) ms）"
                }
            }
            isBenchmarking = false
        }
    }

    private func save() {
        if let d = try? JSONEncoder().encode(config) { UserDefaults.standard.set(d, forKey: Self.configKey) }
    }
}
