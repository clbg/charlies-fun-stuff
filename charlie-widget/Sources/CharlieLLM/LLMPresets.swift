import Foundation

public struct LLMPreset: Sendable, Identifiable {
    public let id: String
    public let label: String
    public let note: String
    public let config: LLMConfig

    public init(id: String, label: String, note: String, config: LLMConfig) {
        self.id = id
        self.label = label
        self.note = note
        self.config = config
    }
}

public enum LLMPresets {
    // TTFT medians measured from Tokyo (Bedrock): jp Haiku 4.5 ≈0.68s, global Sonnet 5.5 ≈0.94s,
    // us Sonnet 5.5 0.72–1.10s, us Haiku 5.5 ≈0.81s.
    // Sonnet 5.5 rejects `thinking: disabled` (use between_tools); Haiku 4.5 rejects `effort`.
    public static let all: [LLMPreset] = [
        // Measured from Tokyo 2026-11-06 (subtitle prompt, 6 runs): jp Sonnet 4.6 534ms median TTFT,
        // jp Haiku 4.5 633ms, us Sonnet 5.5 819ms, global Sonnet 5.5 968ms. No jp profile for Sonnet 5.5.
        LLMPreset(id: "bedrock-jp-sonnet-4-6", label: "Bedrock 东京 Sonnet 4.6", note: "快且准（默认）",
                  config: LLMConfig(kind: .bedrock, model: "jp.anthropic.claude-sonnet-4-6",
                                    awsRegion: "ap-northeast-1", thinking: nil, effort: nil)),
        LLMPreset(id: "bedrock-us-sonnet-5-5", label: "Bedrock 美西 Sonnet 5.5", note: "讲解最准",
                  config: LLMConfig(kind: .bedrock, model: "us.anthropic.claude-sonnet-5-5",
                                    awsRegion: "us-west-2", thinking: "between_tools", effort: "low")),
        LLMPreset(id: "bedrock-global-sonnet-5-5", label: "Bedrock global Sonnet 5.5", note: "全球路由",
                  config: LLMConfig(kind: .bedrock, model: "global.anthropic.claude-sonnet-5-5",
                                    awsRegion: "ap-northeast-1", thinking: "between_tools", effort: "low")),
        LLMPreset(id: "bedrock-jp-haiku-4-5", label: "Bedrock 东京 Haiku 4.5", note: "快，讲得浅",
                  config: LLMConfig(kind: .bedrock, model: "jp.anthropic.claude-haiku-4-5-20251001-v1:0",
                                    awsRegion: "ap-northeast-1", thinking: nil, effort: nil)),
        LLMPreset(id: "bedrock-us-haiku-5-5", label: "Bedrock 美西 Haiku 5.5", note: "较快",
                  config: LLMConfig(kind: .bedrock, model: "us.anthropic.claude-haiku-5-5",
                                    awsRegion: "us-west-2", thinking: "disabled", effort: "low")),
        LLMPreset(id: "anthropic-sonnet-5-5", label: "Anthropic API Sonnet 5.5", note: "需 API key",
                  config: LLMConfig(kind: .anthropic, model: "claude-sonnet-5-5",
                                    baseURL: "https://api.anthropic.com", thinking: "between_tools", effort: "low")),
        LLMPreset(id: "anthropic-haiku-4-5", label: "Anthropic API Haiku 4.5", note: "需 API key",
                  config: LLMConfig(kind: .anthropic, model: "claude-haiku-4-5",
                                    baseURL: "https://api.anthropic.com", thinking: nil, effort: nil)),
        LLMPreset(id: "openai-custom", label: "OpenAI 兼容（自定义）", note: "自己填地址和模型",
                  config: LLMConfig(kind: .openAICompatible, model: "", baseURL: "", thinking: nil, effort: nil)),
    ]

    public static func preset(id: String) -> LLMPreset? { all.first { $0.id == id } }

    /// The preset whose config equals `config`, if any (for showing the current choice in a picker).
    public static func matching(_ config: LLMConfig) -> LLMPreset? { all.first { $0.config == config } }
}
