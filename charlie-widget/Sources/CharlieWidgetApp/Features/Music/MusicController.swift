import Foundation
import Observation

@MainActor
@Observable
final class MusicController: Sendable {

    private static let enabledKey = "CharlieWidget.musicEnabled"
    private static let scriptPathKey = "CharlieWidget.musicScriptPath"
    private static let defaultScriptPath = "/Users/pencheng/projects/amazonVault/scripts/play-random.sh"

    var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey) }
    }

    var scriptPath: String {
        didSet { UserDefaults.standard.set(scriptPath, forKey: Self.scriptPathKey) }
    }

    private var playbackProcess: Process?

    func stopPlayback() {
        guard let process = playbackProcess else { return }
        if process.isRunning { process.terminate() }
        // play-random.sh spawns afplay as a child; terminate() only kills the bash parent.
        // Kill afplay directly to stop audio.
        let killAfplay = Process()
        killAfplay.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        killAfplay.arguments = ["-x", "afplay"]
        try? killAfplay.run()
        playbackProcess = nil
    }

    init() {
        self.isEnabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
        self.scriptPath = UserDefaults.standard.string(forKey: Self.scriptPathKey) ?? Self.defaultScriptPath
    }

    func play(mood: String) {
        guard isEnabled else { return }
        guard FileManager.default.fileExists(atPath: scriptPath) else {
            print("[MusicController] Script not found: \(scriptPath)")
            return
        }

        stopPlayback()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptPath, mood]

        let task = process
        let controller = self
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try task.run()
                task.waitUntilExit()
                Task { @MainActor in
                    if controller.playbackProcess === task {
                        controller.playbackProcess = nil
                    }
                }
            } catch {
                print("[MusicController] Failed to run script: \(error)")
            }
        }

        playbackProcess = process
    }
}
