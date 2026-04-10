import SwiftUI
import AppKit
import Network

@main
struct CharlieWidgetApp: App {

    @State private var store = MessageStore()
    @State private var sessionStore = SessionStore()
    private let server = SocketServer()

    var body: some Scene {
        MenuBarExtra {
            HistoryView(store: store, sessionStore: sessionStore)
                .onAppear {
                    NSApp?.setActivationPolicy(.accessory)
                }
        } label: {
            let dots = sessionStore.sessions.map {
                MenuBarIcon.SessionDot(state: $0.state, agent: $0.agent)
            }
            Image(nsImage: MenuBarIcon.make(
                unreadByLevel: store.unreadCountsByLevel,
                sessionDots: dots
            ))
        }
        .menuBarExtraStyle(.window)
    }

    init() {
        let store = self.store
        let server = self.server

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

        server.start()
    }
}
