import Foundation
import Observation

// MARK: - ToastLevel

enum ToastLevel: String, Codable, Sendable, CaseIterable {
    case info
    case success
    case warning
    case error

    var sfSymbol: String {
        switch self {
        case .info:    return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error:   return "xmark.circle.fill"
        }
    }

    var accentColor: (red: Double, green: Double, blue: Double) {
        switch self {
        case .info:    return (0.2, 0.6, 1.0)
        case .success: return (0.2, 0.8, 0.4)
        case .warning: return (1.0, 0.8, 0.2)
        case .error:   return (1.0, 0.3, 0.3)
        }
    }
}

// MARK: - Message

struct Message: Identifiable, Codable, Sendable {
    let id: UUID
    let timestamp: Date
    let title: String
    let subtitle: String?
    let body: String
    let level: ToastLevel
    var read: Bool

    init(id: UUID = UUID(), timestamp: Date = .now, title: String, subtitle: String? = nil, body: String, level: ToastLevel = .info, read: Bool = false) {
        self.id = id
        self.timestamp = timestamp
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.level = level
        self.read = read
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        title = try container.decode(String.self, forKey: .title)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
        body = try container.decode(String.self, forKey: .body)
        level = try container.decodeIfPresent(ToastLevel.self, forKey: .level) ?? .info
        read = try container.decode(Bool.self, forKey: .read)
    }
}

// MARK: - MessageStore

@MainActor
@Observable
final class MessageStore: Sendable {

    private static let maxMessages = 100

    private static var storeURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("CharlieWidget", isDirectory: true)
        return dir.appendingPathComponent("messages.json")
    }

    // MARK: Observable state

    private(set) var messages: [Message] = []

    var unreadCount: Int {
        messages.filter { !$0.read }.count
    }

    // MARK: Init

    init() {
        messages = Self.loadFromDisk()
    }

    // MARK: Public API

    func addMessage(title: String, subtitle: String? = nil, body: String, level: ToastLevel = .info) {
        let message = Message(title: title, subtitle: subtitle, body: body, level: level)
        messages.insert(message, at: 0)
        trimIfNeeded()
        save()
    }

    func markAsRead(id: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].read = true
        save()
    }

    func deleteMessage(id: UUID) {
        messages.removeAll { $0.id == id }
        save()
    }

    func clearAll() {
        messages.removeAll()
        save()
    }

    // MARK: Persistence

    private func trimIfNeeded() {
        if messages.count > Self.maxMessages {
            messages = Array(messages.prefix(Self.maxMessages))
        }
    }

    private func save() {
        do {
            let dir = Self.storeURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(messages)
            try data.write(to: Self.storeURL, options: .atomic)
        } catch {
            print("[MessageStore] Failed to save: \(error)")
        }
    }

    private static func loadFromDisk() -> [Message] {
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: storeURL)
            let decoded = try JSONDecoder().decode([Message].self, from: data)
            return Array(decoded.prefix(maxMessages))
        } catch {
            print("[MessageStore] Failed to load: \(error)")
            return []
        }
    }
}
