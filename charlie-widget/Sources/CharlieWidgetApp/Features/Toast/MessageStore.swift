import Foundation
import Observation

// MARK: - Message

struct Message: Identifiable, Codable, Sendable {
    let id: UUID
    let timestamp: Date
    let title: String
    let subtitle: String?
    let body: String
    var read: Bool

    init(id: UUID = UUID(), timestamp: Date = .now, title: String, subtitle: String? = nil, body: String, read: Bool = false) {
        self.id = id
        self.timestamp = timestamp
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.read = read
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

    func addMessage(title: String, subtitle: String? = nil, body: String) {
        let message = Message(title: title, subtitle: subtitle, body: body)
        messages.insert(message, at: 0)
        trimIfNeeded()
        save()
    }

    func markAsRead(id: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].read = true
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
