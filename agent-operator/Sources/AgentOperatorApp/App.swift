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
        // CLI smoke-test mode: run MicPipeline instead of launching UI.
        if CommandLine.arguments.contains("--listen") {
            let seconds: Int
            if let idx = CommandLine.arguments.firstIndex(of: "--seconds"),
               idx + 1 < CommandLine.arguments.count,
               let parsed = Int(CommandLine.arguments[idx + 1]) {
                seconds = parsed
            } else {
                seconds = 8
            }

            Task {
                let pipeline = MicPipeline()
                await pipeline.run(listenSeconds: seconds)
                exit(0)
            }

            // Run the run loop so the async task can execute.
            RunLoop.current.run()
        }

        NSApp?.setActivationPolicy(.accessory)
    }
}
