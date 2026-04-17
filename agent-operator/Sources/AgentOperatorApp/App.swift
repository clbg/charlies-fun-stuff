import SwiftUI
import AppKit

@main
struct AgentOperatorApp: App {

    @State private var appState = AppState()
    @State private var listenService: ListenService?
    @State private var hotkeyManager: HotkeyManager?
    @State private var didSetup = false

    var body: some Scene {
        MenuBarExtra {
            VStack(spacing: 0) {}
                .frame(width: 0, height: 0)
                .onAppear { setupIfNeeded() }

            statusRow
            listenButton

            Divider()

            durationMenu

            Divider()

            recentResultsSection

            if let error = appState.lastError {
                Divider()
                Text("Error: \(error)")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Divider()

            Button("Quit") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            menuBarIcon
        }
        .menuBarExtraStyle(.menu)
    }

    // MARK: - Menu bar icon

    @ViewBuilder
    private var menuBarIcon: some View {
        switch appState.status {
        case .idle:
            Image(systemName: "phone.circle")
        case .listening:
            Image(systemName: "mic.fill")
        case .transcribing:
            Image(systemName: "text.bubble")
        case .askingClaude:
            Image(systemName: "brain")
        case .error:
            Image(systemName: "exclamationmark.triangle")
        }
    }

    // MARK: - Status row

    @ViewBuilder
    private var statusRow: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.headline)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Listen button

    @ViewBuilder
    private var listenButton: some View {
        Button(appState.status == .listening ? "■ Stop (⌥L)" : "● Listen (⌥L)") {
            listenService?.toggle()
        }
        .disabled(appState.status != .idle && appState.status != .listening)
    }

    // MARK: - Duration menu

    @ViewBuilder
    private var durationMenu: some View {
        Menu("Duration: \(appState.listenSeconds)s") {
            ForEach([5, 8, 12, 15, 20], id: \.self) { sec in
                Button("\(sec) seconds") {
                    appState.listenSeconds = sec
                }
            }
        }
    }

    // MARK: - Recent results

    @ViewBuilder
    private var recentResultsSection: some View {
        if appState.recentResults.isEmpty {
            Text("No results yet")
                .foregroundStyle(.secondary)
                .font(.caption)
        } else {
            ForEach(appState.recentResults.prefix(5)) { entry in
                Button {} label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Q: \(entry.question)")
                            .font(.caption)
                            .lineLimit(1)
                        Text("A: \(entry.answer)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private var statusColor: Color {
        switch appState.status {
        case .idle: .green
        case .listening: .red
        case .transcribing: .orange
        case .askingClaude: .blue
        case .error: .red
        }
    }

    private var statusText: String {
        switch appState.status {
        case .idle: "Ready"
        case .listening: "Listening..."
        case .transcribing: "Transcribing..."
        case .askingClaude: "Asking Claude..."
        case .error: "Error"
        }
    }

    // MARK: - Setup

    @MainActor
    private func setupIfNeeded() {
        guard !didSetup else { return }
        didSetup = true

        let service = ListenService(appState: appState)
        listenService = service

        let hk = HotkeyManager()
        hk.onHotkeyPressed = { [weak service] in
            service?.toggle()
        }
        hotkeyManager = hk
    }

    // MARK: - Init

    init() {
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
            RunLoop.current.run()
        }

        NSApp?.setActivationPolicy(.accessory)
    }
}
