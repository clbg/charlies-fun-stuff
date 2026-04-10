import Foundation

// MARK: - AgentKind

enum AgentKind: String, Codable, Sendable, CaseIterable {
    case claude
    case gemini
    case codex
    case kiro
    case unknown

    var displayName: String {
        switch self {
        case .claude:  return "Claude Code"
        case .gemini:  return "Gemini CLI"
        case .codex:   return "Codex CLI"
        case .kiro:    return "Kiro"
        case .unknown: return "Agent"
        }
    }

    var sfSymbol: String {
        switch self {
        case .claude:  return "c.square.fill"
        case .gemini:  return "g.square.fill"
        case .codex:   return "o.square.fill"
        case .kiro:    return "k.square.fill"
        case .unknown: return "questionmark.square.fill"
        }
    }

    /// Single letter shown inside menu-bar session dots.
    var dotLetter: String {
        switch self {
        case .claude:  return "C"
        case .gemini:  return "G"
        case .codex:   return "X"
        case .kiro:    return "K"
        case .unknown: return "?"
        }
    }
}

// MARK: - SessionState

enum SessionState: String, Codable, Sendable {
    case running
    case idle
    case pending

    var sfSymbol: String {
        switch self {
        case .running: return "circle.fill"
        case .idle:    return "circle"
        case .pending: return "exclamationmark.circle.fill"
        }
    }

    var label: String {
        switch self {
        case .running: return "running"
        case .idle:    return "idle"
        case .pending: return "waiting"
        }
    }
}

// MARK: - Session

struct Session: Identifiable, Codable, Sendable {
    let sessionId: String
    let agent: AgentKind
    let cwd: String
    var state: SessionState
    var lastUpdated: Date
    var pid: Int?

    var id: String { sessionId }

    /// Last 2 path components of cwd, e.g. "charlies-fun-stuff/widget"
    var projectName: String {
        let components = cwd.split(separator: "/")
        let suffix = components.suffix(2)
        return suffix.joined(separator: "/")
    }

    /// Whether the owning process has exited
    var isProcessDead: Bool {
        guard let pid else { return false }
        return kill(pid_t(pid), 0) != 0
    }

    /// Whether session hasn't updated in 5+ minutes (fallback for sessions without PID)
    var isStale: Bool {
        abs(lastUpdated.timeIntervalSinceNow) > 5 * 60
    }

    /// Session should be removed: process dead, no PID (legacy), or TTL expired
    var shouldRemove: Bool {
        guard let _ = pid else { return true }  // no PID = legacy format, clean up
        return isProcessDead || isStale
    }

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case agent
        case cwd
        case state
        case lastUpdated = "last_updated"
        case pid
    }
}
