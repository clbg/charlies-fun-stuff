import SwiftUI
import AppKit
import Network

@main
struct CharlieWidgetApp: App {

    @State private var store = MessageStore()
    private let server = SocketServer()

    var body: some Scene {
        MenuBarExtra {
            HistoryView(store: store)
                .onAppear {
                    NSApp?.setActivationPolicy(.accessory)
                }
        } label: {
            Image(nsImage: MenuBarIcon.make(badgeCount: store.unreadCount))
        }
        .menuBarExtraStyle(.window)
    }

    init() {
        let store = self.store
        let server = self.server

        server.onToast = { title, subtitle, body in
            store.addMessage(title: title, subtitle: subtitle, body: body)
            ToastWindow.show(title: title, subtitle: subtitle, body: body)
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
