import Foundation
import Observation

// MARK: - SessionStore

@MainActor
@Observable
final class SessionStore: Sendable {

    private(set) var sessions: [Session] = []

    var onAggregateTransition: (@MainActor @Sendable (_ mood: String) -> Void)?

    private var dispatchSource: (any DispatchSourceFileSystemObject)?
    private var directoryFD: Int32 = -1
    private var debounceTask: Task<Void, Never>?
    private var sweepTask: Task<Void, Never>?
    private var wasAnyPending: Bool = false
    private var wasAllIdle: Bool = true

    // MARK: Computed

    var activeSessions: [Session] {
        sessions
    }

    var runningCount: Int {
        sessions.filter { $0.state == .running }.count
    }

    var pendingCount: Int {
        sessions.filter { $0.state == .pending }.count
    }

    var idleCount: Int {
        sessions.filter { $0.state == .idle }.count
    }

    // MARK: Init

    init() {
        ensureDirectory()
        reload()
        startWatching()
        startSweepTimer()
    }

    deinit {
        stopWatching()
    }

    // MARK: Directory

    nonisolated static var sessionsDirectoryURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("CharlieWidget", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
    }

    private func ensureDirectory() {
        try? FileManager.default.createDirectory(
            at: Self.sessionsDirectoryURL,
            withIntermediateDirectories: true
        )
    }

    // MARK: FSEvents via DispatchSource

    nonisolated func startWatching() {
        let path = Self.sessionsDirectoryURL.path
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else {
            print("[SessionStore] Failed to open directory for watching: \(path)")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: .global(qos: .userInitiated)
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.debounceTask?.cancel()
                self.debounceTask = Task {
                    try? await Task.sleep(for: .milliseconds(100))
                    guard !Task.isCancelled else { return }
                    self.reload()
                }
            }
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()

        Task { @MainActor in
            self.directoryFD = fd
            self.dispatchSource = source
        }
    }

    nonisolated func stopWatching() {
        Task { @MainActor [weak self] in
            self?.dispatchSource?.cancel()
            self?.dispatchSource = nil
            self?.directoryFD = -1
        }
    }

    // MARK: Periodic sweep (catch dead processes when no FSEvents fire)

    private func startSweepTimer() {
        sweepTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { break }
                self?.reload()
            }
        }
    }

    // MARK: Reload

    func reload() {
        let fm = FileManager.default
        let dir = Self.sessionsDirectoryURL

        guard let files = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil
        ) else {
            sessions = []
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var newSessions: [Session] = []

        for file in files where file.pathExtension == "json" && !file.lastPathComponent.hasPrefix(".") {
            guard let data = try? Data(contentsOf: file),
                  let session = try? decoder.decode(Session.self, from: data)
            else { continue }

            if session.shouldRemove {
                try? fm.removeItem(at: file)
                continue
            }

            newSessions.append(session)
        }

        sessions = newSessions.sorted { $0.lastUpdated > $1.lastUpdated }

        // Aggregate state transition detection
        let allIdle = !sessions.isEmpty && sessions.allSatisfy { $0.state == .idle }
        let anyPending = sessions.contains { $0.state == .pending }

        if anyPending && !wasAnyPending {
            onAggregateTransition?("tense")
        } else if allIdle && !wasAllIdle {
            onAggregateTransition?("calm")
        }

        wasAnyPending = anyPending
        wasAllIdle = allIdle || sessions.isEmpty
    }

    // MARK: Clear

    func clearAll() {
        let fm = FileManager.default
        let dir = Self.sessionsDirectoryURL
        if let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension == "json" {
                try? fm.removeItem(at: file)
            }
        }
        sessions = []
        wasAnyPending = false
        wasAllIdle = true
    }
}
