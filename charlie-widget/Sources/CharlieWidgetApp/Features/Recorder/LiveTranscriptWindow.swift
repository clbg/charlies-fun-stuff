import AppKit
import SwiftUI
import Observation

/// Owns a floating NSPanel that displays the live transcript.
///
/// The window is:
/// - `.floating` level — above normal apps, below menu bar
/// - `.nonactivatingPanel` — clicking inside does not steal focus from the user's current app
/// - Resizable, draggable, with a standard title bar + close button
/// - Close button = hide (preserves state). Real teardown only on app quit.
/// - Frame + last-visible state persisted to UserDefaults.
@MainActor
@Observable
final class LiveTranscriptWindowController: NSObject, NSWindowDelegate {

    private(set) var isVisible: Bool = false

    private var panel: NSPanel?
    private var recorderStore: RecorderStore?
    private var frameSaveWorkItem: DispatchWorkItem?

    // MARK: - UserDefaults

    private static let frameKey = "CharlieWidget.pinnedTranscript.frame"
    private static let lastVisibleKey = "CharlieWidget.pinnedTranscript.lastVisible"

    private static let defaultWidth: CGFloat = 360
    private static let defaultHeight: CGFloat = 420
    private static let minWidth: CGFloat = 320
    private static let minHeight: CGFloat = 180

    // MARK: - Public API

    func toggle(store: RecorderStore) {
        if isVisible {
            hide()
        } else {
            show(store: store)
        }
    }

    func show(store: RecorderStore) {
        recorderStore = store
        let panel = ensurePanel(store: store)
        panel.orderFrontRegardless()
        isVisible = true
        UserDefaults.standard.set(true, forKey: Self.lastVisibleKey)
    }

    func hide() {
        panel?.orderOut(nil)
        isVisible = false
        UserDefaults.standard.set(false, forKey: Self.lastVisibleKey)
    }

    /// Called once at app startup. Reopens the window if it was visible when the app last quit.
    func restoreIfNeeded(store: RecorderStore) {
        let lastVisible = UserDefaults.standard.bool(forKey: Self.lastVisibleKey)
        if lastVisible {
            show(store: store)
        }
    }

    // MARK: - Panel creation

    private func ensurePanel(store: RecorderStore) -> NSPanel {
        if let existing = panel {
            // Re-root content in case the store instance changed (shouldn't in practice)
            return existing
        }

        let initialFrame = loadSavedFrame() ?? defaultFrame()

        // NOTE: Keep collectionBehavior minimal. On macOS 15, combining
        // .fullScreenAuxiliary or .moveToActiveSpace with .utilityWindow
        // styleMask can deadlock inside CGS during init.
        let panel = NSPanel(
            contentRect: initialFrame,
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces]
        panel.isReleasedWhenClosed = false
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.minSize = NSSize(width: Self.minWidth, height: Self.minHeight)
        panel.delegate = self

        let content = LiveTranscriptPinnedView(recorderStore: store)
        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = panel.contentView!.bounds
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView?.addSubview(hostingView)

        self.panel = panel
        return panel
    }

    private func defaultFrame() -> NSRect {
        guard let screen = NSScreen.main else {
            return NSRect(x: 100, y: 100, width: Self.defaultWidth, height: Self.defaultHeight)
        }
        let vf = screen.visibleFrame
        let x = vf.maxX - Self.defaultWidth - 16
        let y = vf.maxY - Self.defaultHeight - 16
        return NSRect(x: x, y: y, width: Self.defaultWidth, height: Self.defaultHeight)
    }

    // MARK: - Frame persistence

    private func loadSavedFrame() -> NSRect? {
        guard let str = UserDefaults.standard.string(forKey: Self.frameKey) else { return nil }
        let r = NSRectFromString(str)
        // Reject off-screen or zero-size frames
        guard r.width >= Self.minWidth, r.height >= Self.minHeight else { return nil }
        let onAnyScreen = NSScreen.screens.contains { $0.visibleFrame.intersects(r) }
        return onAnyScreen ? r : nil
    }

    private func saveFrame() {
        guard let panel else { return }
        let str = NSStringFromRect(panel.frame)
        UserDefaults.standard.set(str, forKey: Self.frameKey)
    }

    private func scheduleFrameSave() {
        frameSaveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in self?.saveFrame() }
        }
        frameSaveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    // MARK: - NSWindowDelegate

    nonisolated func windowShouldClose(_ sender: NSWindow) -> Bool {
        // X button = hide, not close. Preserve state.
        Task { @MainActor [weak self] in self?.hide() }
        return false
    }

    nonisolated func windowDidMove(_ notification: Notification) {
        Task { @MainActor [weak self] in self?.scheduleFrameSave() }
    }

    nonisolated func windowDidResize(_ notification: Notification) {
        Task { @MainActor [weak self] in self?.scheduleFrameSave() }
    }
}
