import SwiftUI
import AppKit
import Network

@main
struct CharlieWidgetApp: App {

    @State private var store = MessageStore()
    @State private var sessionStore = SessionStore()
    @State private var recorderStore = RecorderStore()
    private let server = SocketServer()

    var body: some Scene {
        MenuBarExtra {
            HistoryView(store: store, sessionStore: sessionStore, recorderStore: recorderStore)
                .onAppear {
                    NSApp?.setActivationPolicy(.accessory)
                }
        } label: {
            let dots = sessionStore.sessions.map {
                MenuBarIcon.SessionDot(state: $0.state, agent: $0.agent)
            }
            Image(nsImage: MenuBarIcon.make(
                unreadByLevel: store.unreadCountsByLevel,
                sessionDots: dots,
                isRecording: recorderStore.state == .recording
            ))
        }
        .menuBarExtraStyle(.window)
    }

    init() {
        let store = self.store
        let server = self.server
        let recorderStore = self.recorderStore

        server.onToast = { title, subtitle, body, level in
            store.addMessage(title: title, subtitle: subtitle, body: body, level: level)
            if !store.muted {
                ToastWindow.show(title: title, subtitle: subtitle, body: body, level: level)
            }
        }

        server.onHistoryRequest = { connection in
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(store.messages),
               let json = String(data: data, encoding: .utf8) {
                server.send(json + "\n", to: connection)
            } else {
                server.send("[]\n", to: connection)
            }
        }

        server.onClearRequest = {
            store.clearAll()
        }

        server.onRecordStart = { source, connection in
            Task {
                let wasIdle = recorderStore.state == .idle
                await recorderStore.startRecording(source: source)
                if wasIdle, recorderStore.state == .recording {
                    server.send("{\"ok\":true}\n", to: connection)
                } else {
                    let err = recorderStore.lastError ?? "unknown"
                    server.send("{\"error\":\"\(err)\"}\n", to: connection)
                }
            }
        }

        server.onRecordStop = { connection in
            Task {
                await recorderStore.stopRecording()
                server.send("{\"ok\":true}\n", to: connection)
            }
        }

        server.onRecordStatus = { connection in
            let state = recorderStore.state.rawValue
            let elapsed = Int(recorderStore.elapsedSeconds)
            let source = recorderStore.currentRecording?.source.rawValue ?? ""
            server.send("{\"state\":\"\(state)\",\"elapsed_seconds\":\(elapsed),\"source\":\"\(source)\"}\n", to: connection)
        }

        server.onRecordList = { connection in
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(recorderStore.todayRecordings),
               let json = String(data: data, encoding: .utf8) {
                server.send(json + "\n", to: connection)
            } else {
                server.send("[]\n", to: connection)
            }
        }

        server.onRecordDelete = { recordingId, connection in
            if recorderStore.deleteRecording(id: recordingId) {
                server.send("{\"ok\":true}\n", to: connection)
            } else {
                let err = recorderStore.lastError ?? "unknown"
                server.send("{\"error\":\"\(err)\"}\n", to: connection)
            }
        }

        server.onRecordRename = { recordingId, name, connection in
            if recorderStore.renameRecording(id: recordingId, name: name) {
                server.send("{\"ok\":true}\n", to: connection)
            } else {
                let err = recorderStore.lastError ?? "unknown"
                server.send("{\"error\":\"\(err)\"}\n", to: connection)
            }
        }

        server.onRecordTranscribe = { recordingId, language, connection in
            Task {
                if let text = await recorderStore.transcribe(recordingId: recordingId, language: language) {
                    let escaped = text
                        .replacingOccurrences(of: "\\", with: "\\\\")
                        .replacingOccurrences(of: "\"", with: "\\\"")
                        .replacingOccurrences(of: "\n", with: "\\n")
                    server.send("{\"ok\":true,\"text\":\"\(escaped)\"}\n", to: connection)
                } else {
                    let err = recorderStore.lastError ?? "unknown"
                    server.send("{\"error\":\"\(err)\"}\n", to: connection)
                }
            }
        }

        server.onRecordDiarize = { recordingId, connection in
            Task {
                if let text = await recorderStore.diarize(recordingId: recordingId) {
                    let escaped = text
                        .replacingOccurrences(of: "\\", with: "\\\\")
                        .replacingOccurrences(of: "\"", with: "\\\"")
                        .replacingOccurrences(of: "\n", with: "\\n")
                    server.send("{\"ok\":true,\"text\":\"\(escaped)\"}\n", to: connection)
                } else {
                    let err = recorderStore.lastError ?? "unknown"
                    server.send("{\"error\":\"\(err)\"}\n", to: connection)
                }
            }
        }

        server.onRecordIdentify = { recordingId, connection in
            Task {
                if let text = await recorderStore.identify(recordingId: recordingId) {
                    let escaped = text
                        .replacingOccurrences(of: "\\", with: "\\\\")
                        .replacingOccurrences(of: "\"", with: "\\\"")
                        .replacingOccurrences(of: "\n", with: "\\n")
                    server.send("{\"ok\":true,\"text\":\"\(escaped)\"}\n", to: connection)
                } else {
                    let err = recorderStore.lastError ?? "unknown"
                    server.send("{\"error\":\"\(err)\"}\n", to: connection)
                }
            }
        }

        server.onRecordSummary = { dateStr, connection in
            Task {
                let date: Date
                if dateStr.isEmpty {
                    date = Date()
                } else {
                    let fmt = DateFormatter()
                    fmt.dateFormat = "yyyy-MM-dd"
                    guard let parsed = fmt.date(from: dateStr) else {
                        server.send("{\"error\":\"Invalid date format, use YYYY-MM-DD\"}\n", to: connection)
                        return
                    }
                    date = parsed
                }
                do {
                    let summary = try await recorderStore.generateDailySummary(for: date)
                    let encoder = JSONEncoder()
                    encoder.dateEncodingStrategy = .iso8601
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let data = try encoder.encode(summary)
                    if let json = String(data: data, encoding: .utf8) {
                        server.send(json + "\n", to: connection)
                    }
                } catch {
                    server.send("{\"error\":\"\(error.localizedDescription)\"}\n", to: connection)
                }
            }
        }

        server.start()
    }
}
