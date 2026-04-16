import Foundation

// MARK: - TranslationProvider Protocol

/// Translates text between languages.
protocol TranslationProvider: Sendable {
    func translate(text: String, from sourceLanguage: String, to targetLanguage: String) async throws -> String
}

// MARK: - MockTranslationProvider

/// Returns bracketed "translated" text for pipeline testing.
struct MockTranslationProvider: TranslationProvider {
    func translate(text: String, from sourceLanguage: String, to targetLanguage: String) async throws -> String {
        "[translated] \(text)"
    }
}

// MARK: - AWSTranslateProvider

/// Amazon Translate integration (stubbed).
///
/// ## API Flow (when implemented)
///
/// 1. Create `TranslateClient` with region from config
/// 2. Build `TranslateTextInput`:
///    - `text`: source text (max 10,000 bytes per request)
///    - `sourceLanguageCode`: ISO 639-1 (e.g. "ja", "zh", "en") or "auto"
///    - `targetLanguageCode`: ISO 639-1 target (e.g. "en")
/// 3. Call `translateText()` → `TranslateTextOutput.translatedText`
///
/// ## Pricing
///
/// - $15 per million characters (standard)
/// - Free tier: 2M chars/month for 12 months
/// - Batch translation available for large volumes
///
/// ## Dependencies (when implemented)
///
/// - `aws-sdk-swift` → `AWSTranslate` package
/// - IAM credentials via `~/.aws/credentials` or environment
struct AWSTranslateProvider: TranslationProvider {

    struct Config: Codable, Sendable {
        let region: String
        let targetLanguage: String

        static let `default` = Config(region: "us-west-2", targetLanguage: "en")
    }

    let config: Config

    init(config: Config = .default) {
        self.config = config
    }

    func translate(text: String, from sourceLanguage: String, to targetLanguage: String) async throws -> String {
        // TODO: Implement with aws-sdk-swift AWSTranslate
        // let client = try TranslateClient(region: config.region)
        // let input = TranslateTextInput(
        //     sourceLanguageCode: sourceLanguage,
        //     targetLanguageCode: targetLanguage,
        //     text: text
        // )
        // let output = try await client.translateText(input: input)
        // return output.translatedText ?? text
        throw TranslationError.notImplemented("AWS Translate integration not yet available. Add aws-sdk-swift dependency and implement.")
    }
}

// MARK: - TranslationError

enum TranslationError: Error, LocalizedError {
    case notImplemented(String)
    case translationFailed(String)

    var errorDescription: String? {
        switch self {
        case .notImplemented(let msg): msg
        case .translationFailed(let msg): "Translation failed: \(msg)"
        }
    }
}
