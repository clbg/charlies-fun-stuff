import Foundation

// MARK: - Configuration

public enum LLMProviderKind: String, Codable, CaseIterable, Sendable {
    case bedrock, anthropic, openAICompatible
}

public struct LLMConfig: Codable, Equatable, Sendable {
    public var kind: LLMProviderKind
    /// bedrock: inference profile id (e.g. "us.anthropic.claude-sonnet-5-5");
    /// anthropic: model name (e.g. "claude-sonnet-5-5"); openAICompatible: any.
    public var model: String
    /// bedrock only. Profile name passed to `aws configure export-credentials`.
    public var awsProfile: String
    /// bedrock only.
    public var awsRegion: String
    /// openAICompatible: e.g. "https://api.deepseek.com/v1" (the provider appends `/chat/completions`).
    /// anthropic: empty means "https://api.anthropic.com".
    public var baseURL: String
    /// anthropic/bedrock: "disabled" | "between_tools" | "adaptive"; nil omits the `thinking` field.
    public var thinking: String?
    /// anthropic/bedrock: `output_config.effort` (e.g. "low"); nil omits the field.
    public var effort: String?

    public init(
        kind: LLMProviderKind = .bedrock,
        model: String = "us.anthropic.claude-sonnet-5-5",
        awsProfile: String = "claude-code",
        awsRegion: String = "us-west-2",
        baseURL: String = "",
        thinking: String? = nil,
        effort: String? = nil
    ) {
        self.kind = kind
        self.model = model
        self.awsProfile = awsProfile
        self.awsRegion = awsRegion
        self.baseURL = baseURL
        self.thinking = thinking
        self.effort = effort
    }

    public static let `default` = LLMConfig(
        kind: .bedrock,
        model: "us.anthropic.claude-sonnet-5-5",
        awsProfile: "claude-code",
        awsRegion: "us-west-2",
        baseURL: "",
        thinking: "between_tools",
        effort: "low"
    )

    // Tolerant decoding: missing keys fall back to defaults so saved settings survive schema growth.
    private enum CodingKeys: String, CodingKey {
        case kind, model, awsProfile, awsRegion, baseURL, thinking, effort
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = LLMConfig()
        kind = try c.decodeIfPresent(LLMProviderKind.self, forKey: .kind) ?? d.kind
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? d.model
        awsProfile = try c.decodeIfPresent(String.self, forKey: .awsProfile) ?? d.awsProfile
        awsRegion = try c.decodeIfPresent(String.self, forKey: .awsRegion) ?? d.awsRegion
        baseURL = try c.decodeIfPresent(String.self, forKey: .baseURL) ?? d.baseURL
        thinking = try c.decodeIfPresent(String.self, forKey: .thinking)
        effort = try c.decodeIfPresent(String.self, forKey: .effort)
    }
}

// MARK: - Request / events

public enum LLMContent: Sendable {
    case text(String)
    case imagePNG(Data)
}

public struct LLMMessage: Sendable {
    /// "user" or "assistant".
    public var role: String
    public var content: [LLMContent]
    public init(role: String, content: [LLMContent]) {
        self.role = role
        self.content = content
    }
}

public struct LLMRequest: Sendable {
    public var system: String
    public var messages: [LLMMessage]
    public var maxTokens: Int
    public init(system: String, messages: [LLMMessage], maxTokens: Int) {
        self.system = system
        self.messages = messages
        self.maxTokens = maxTokens
    }
}

public enum LLMEvent: Sendable {
    case text(String)
    /// ttftMs: stream start (incl. credential lookup + signing) -> first text delta.
    /// totalMs: stream start -> end of response. If no text arrived, ttftMs == totalMs.
    case done(ttftMs: Int, totalMs: Int)
}

public protocol LLMProvider: Sendable {
    /// Cancelling the consuming Task (or dropping the stream) cancels the HTTP request.
    func stream(_ request: LLMRequest) -> AsyncThrowingStream<LLMEvent, Error>
    /// Fetch credentials and open the TLS connection (a max_tokens=1 call). Never throws.
    func warmUp() async
}

public enum LLM {
    public static func provider(for config: LLMConfig) -> any LLMProvider {
        switch config.kind {
        case .bedrock: return BedrockProvider(config: config)
        case .anthropic: return AnthropicProvider(config: config)
        case .openAICompatible: return OpenAICompatibleProvider(config: config)
        }
    }
}

// MARK: - Errors

public enum LLMError: Error, LocalizedError, Sendable, Equatable {
    case missingAPIKey(LLMProviderKind)
    case awsCLINotFound
    case credentials(String)
    case http(status: Int, message: String)
    case stream(String)
    case invalidConfig(String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey(let kind):
            return "No API key for \(kind.rawValue). Set one in Settings (stored in Keychain)."
        case .awsCLINotFound:
            return "AWS CLI (`aws`) not found in /opt/homebrew/bin, /usr/local/bin, ~/.local/bin, ~/.aki/bin or the login shell PATH."
        case .credentials(let msg):
            return "AWS credentials unavailable: \(msg) — refresh with `mwinit` / `ada credentials update`."
        case .http(let status, let message):
            return "HTTP \(status): \(message)"
        case .stream(let msg):
            return "Stream error: \(msg)"
        case .invalidConfig(let msg):
            return "Invalid LLM config: \(msg)"
        }
    }
}

// MARK: - Debug logging (stderr, opt-in via CHARLIE_LLM_DEBUG=1). Never logs secrets.

enum LLMDebug {
    static let enabled = ProcessInfo.processInfo.environment["CHARLIE_LLM_DEBUG"] == "1"
    static func log(_ msg: @autoclosure () -> String) {
        guard enabled else { return }
        FileHandle.standardError.write(Data("[CharlieLLM] \(msg())\n".utf8))
    }
}
