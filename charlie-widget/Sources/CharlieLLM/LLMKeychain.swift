import Foundation
import Security

/// API keys live in the login Keychain as generic passwords: service "com.charlie.widget.llm", account = kind.rawValue.
public enum LLMKeychain {
    public static let service = "com.charlie.widget.llm"

    public static func apiKey(for kind: LLMProviderKind) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: kind.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data, let s = String(data: data, encoding: .utf8), !s.isEmpty else { return nil }
        return s
    }

    /// nil (or empty) deletes the item.
    public static func setAPIKey(_ key: String?, for kind: LLMProviderKind) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: kind.rawValue,
        ]
        SecItemDelete(base as CFDictionary)
        guard let key, !key.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(key.utf8)
        add[kSecAttrLabel as String] = "Charlie Widget LLM (\(kind.rawValue))"
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    /// Keychain first, then env (`ANTHROPIC_API_KEY` / `OPENAI_API_KEY` / `GEMINI_API_KEY` / `DEEPSEEK_API_KEY`)
    /// — the env fallback is for llm-smoke.
    static func resolvedKeyOrNil(for kind: LLMProviderKind) -> String? {
        if let k = apiKey(for: kind) { return k }
        let env = ProcessInfo.processInfo.environment
        switch kind {
        case .anthropic: return env["ANTHROPIC_API_KEY"].flatMap { $0.isEmpty ? nil : $0 }
        case .openAICompatible: return env["OPENAI_API_KEY"].flatMap { $0.isEmpty ? nil : $0 }
        case .gemini: return env["GEMINI_API_KEY"].flatMap { $0.isEmpty ? nil : $0 }
        case .deepseek: return env["DEEPSEEK_API_KEY"].flatMap { $0.isEmpty ? nil : $0 }
        case .bedrock: return nil
        }
    }

    static func resolvedKey(for kind: LLMProviderKind) throws -> String {
        guard let k = resolvedKeyOrNil(for: kind) else { throw LLMError.missingAPIKey(kind) }
        return k
    }
}
