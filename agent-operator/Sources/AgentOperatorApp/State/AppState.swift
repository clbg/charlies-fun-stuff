import Foundation

// MARK: - AppState

/// Observable model that drives the menu-bar UI.
///
/// Uses the Observation framework (`@Observable`) — requires macOS 14+.
/// All properties are read/written on `@MainActor`.
@Observable
@MainActor
final class AppState {

    // MARK: - Status

    enum Status: String {
        case idle
        case listening
        case transcribing
        case askingClaude
        case error
    }

    // MARK: - QAEntry

    struct QAEntry: Identifiable {
        let id = UUID()
        let question: String
        let answer: String
        let timestamp: Date
    }

    // MARK: - Published state

    var status: Status = .idle
    var listenSeconds: Int = 8
    var recentResults: [QAEntry] = []
    var lastError: String?

    // MARK: - Helpers

    /// Insert a new Q&A result at the front, keeping at most 10 entries.
    func addResult(question: String, answer: String) {
        recentResults.insert(
            QAEntry(question: question, answer: answer, timestamp: Date()),
            at: 0
        )
        if recentResults.count > 10 {
            recentResults.removeLast()
        }
    }
}
