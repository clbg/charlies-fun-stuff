import SwiftUI
import AppKit

@main
struct AgentOperatorApp: App {

    var body: some Scene {
        MenuBarExtra("AgentOperator", systemImage: "phone.circle") {
            Text("Hello from AgentOperator")
                .padding(.bottom, 4)

            Divider()

            Button("Quit") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .menuBarExtraStyle(.menu)
    }

    init() {
        NSApp?.setActivationPolicy(.accessory)
    }
}
