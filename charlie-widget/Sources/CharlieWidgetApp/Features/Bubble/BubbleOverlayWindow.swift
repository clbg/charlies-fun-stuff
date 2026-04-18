import AppKit
import SwiftUI
import Observation

@MainActor
@Observable
final class BubbleOverlayController {

    private static let enabledKey = "CharlieWidget.bubbleEnabled"

    private(set) var bubbles: [Bubble] = []
    private(set) var dismissedIds: Set<String> = []
    var isEnabled: Bool = UserDefaults.standard.object(forKey: "CharlieWidget.bubbleEnabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            if isEnabled {
                showWindow()
                startAnimation()
            } else {
                stopAnimation()
                hideWindow()
                bubbles.removeAll()
                dismissedIds.removeAll()
            }
        }
    }

    private var window: NSWindow?
    private var animationTask: Task<Void, Never>?
    private var observationTask: Task<Void, Never>?

    private static let maxBubbles = 30

    // MARK: - Session Observation

    func observeSessions(_ store: SessionStore) {
        if isEnabled {
            showWindow()
            startAnimation()
        }
        observationTask?.cancel()
        observationTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.isEnabled {
                    self.syncBubbles(with: store.sessions)
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    func dismissBubble(id: String) {
        bubbles.removeAll { $0.id == id }
        dismissedIds.insert(id)
    }

    func dismissAll() {
        for bubble in bubbles {
            dismissedIds.insert(bubble.id)
        }
        bubbles.removeAll()
    }

    private func syncBubbles(with sessions: [Session]) {
        var desiredIds: Set<String> = []

        for session in sessions {
            switch session.state {
            case .pending:
                desiredIds.insert(session.sessionId)
                if dismissedIds.contains(session.sessionId) { continue }
                if let idx = bubbles.firstIndex(where: { $0.id == session.sessionId }) {
                    bubbles[idx].isWarm = true
                } else {
                    addBubble(sessionId: session.sessionId, agentLetter: session.agent.dotLetter, isWarm: true)
                }
            case .idle:
                desiredIds.insert(session.sessionId)
                if dismissedIds.contains(session.sessionId) { continue }
                if let idx = bubbles.firstIndex(where: { $0.id == session.sessionId }) {
                    bubbles[idx].isWarm = false
                } else {
                    addBubble(sessionId: session.sessionId, agentLetter: session.agent.dotLetter, isWarm: false)
                }
            case .running:
                dismissedIds.remove(session.sessionId)
            }
        }

        let sessionIds = Set(sessions.map(\.sessionId))
        for id in dismissedIds where !sessionIds.contains(id) {
            dismissedIds.remove(id)
        }

        bubbles.removeAll { !desiredIds.contains($0.id) }
    }

    private func addBubble(sessionId: String, agentLetter: String, isWarm: Bool) {
        guard let screen = NSScreen.screens.first else { return }
        let frame = screen.visibleFrame
        let margin: CGFloat = 180

        let bubble = Bubble(
            id: sessionId,
            agentLetter: agentLetter,
            isWarm: isWarm,
            position: CGPoint(
                x: .random(in: (frame.minX + margin)...(frame.maxX - margin)),
                y: .random(in: (frame.minY + margin)...(frame.maxY - margin))
            ),
            velocity: CGPoint(
                x: .random(in: -0.5...0.5),
                y: .random(in: -0.5...0.5)
            ),
            size: .random(in: 105...165)
        )
        bubbles.append(bubble)

        if bubbles.count > Self.maxBubbles {
            bubbles.removeFirst(bubbles.count - Self.maxBubbles)
        }
    }

    // MARK: - Animation Loop

    private func startAnimation() {
        animationTask?.cancel()
        animationTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.tick()
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    private func stopAnimation() {
        animationTask?.cancel()
        animationTask = nil
    }

    private func tick() {
        guard let screen = NSScreen.screens.first else { return }
        let frame = screen.visibleFrame

        for i in bubbles.indices {
            bubbles[i].position.x += bubbles[i].velocity.x
            bubbles[i].position.y += bubbles[i].velocity.y

            let r = bubbles[i].size
            if bubbles[i].position.x - r < frame.minX || bubbles[i].position.x + r > frame.maxX {
                bubbles[i].velocity.x *= -1
                bubbles[i].position.x = min(max(bubbles[i].position.x, frame.minX + r), frame.maxX - r)
            }
            if bubbles[i].position.y - r < frame.minY || bubbles[i].position.y + r > frame.maxY {
                bubbles[i].velocity.y *= -1
                bubbles[i].position.y = min(max(bubbles[i].position.y, frame.minY + r), frame.maxY - r)
            }
        }
    }

    // MARK: - Window Management

    private func showWindow() {
        if window != nil { return }
        guard let screen = NSScreen.screens.first else { return }

        let w = BubbleWindow(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        w.bubbleController = self
        w.backgroundColor = .clear
        w.isOpaque = false
        w.level = .floating
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        w.hasShadow = false
        w.setFrame(screen.frame, display: true)

        let contentView = BubbleContentView(frame: w.frame)
        contentView.bubbleController = self
        w.contentView = contentView

        let controller = self
        let hostingView = NSHostingView(rootView: BubbleOverlayBindingView(controller: controller))
        hostingView.frame = contentView.bounds
        hostingView.autoresizingMask = [.width, .height]
        contentView.addSubview(hostingView)

        w.orderFrontRegardless()
        window = w
    }

    private func hideWindow() {
        window?.orderOut(nil)
        window = nil
    }
}

// MARK: - BubbleWindow (click-through except on bubbles)

private class BubbleWindow: NSWindow {
    weak var bubbleController: BubbleOverlayController?

    override func mouseDown(with event: NSEvent) {
        guard let controller = bubbleController else { return }
        let loc = event.locationInWindow
        // NSWindow coordinates: origin bottom-left, same as bubble positions
        for bubble in controller.bubbles {
            let dx = loc.x - bubble.position.x
            let dy = loc.y - bubble.position.y
            if dx * dx + dy * dy <= bubble.size * bubble.size {
                controller.dismissBubble(id: bubble.id)
                return
            }
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Overlay Content View (passes non-bubble clicks through, mouse-dismiss)

private class BubbleContentView: NSView {
    weak var bubbleController: BubbleOverlayController?
    nonisolated(unsafe) private var mouseMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            startMouseMonitor()
        } else {
            stopMouseMonitor()
        }
    }

    private func startMouseMonitor() {
        stopMouseMonitor()
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            Task { @MainActor in
                self?.checkMouseOverBubble(event: event)
            }
        }
    }

    private func stopMouseMonitor() {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
    }

    private func checkMouseOverBubble(event: NSEvent) {
        guard let controller = bubbleController, !controller.bubbles.isEmpty else { return }
        let loc = NSEvent.mouseLocation
        for bubble in controller.bubbles {
            let dx = loc.x - bubble.position.x
            let dy = loc.y - bubble.position.y
            if dx * dx + dy * dy <= bubble.size * bubble.size {
                controller.dismissAll()
                return
            }
        }
    }

    override func hitTest(_ aPoint: NSPoint) -> NSView? {
        guard let controller = bubbleController else { return nil }
        let loc = convert(aPoint, from: superview)
        for bubble in controller.bubbles {
            let dx = loc.x - bubble.position.x
            let dy = loc.y - bubble.position.y
            if dx * dx + dy * dy <= bubble.size * bubble.size {
                return self
            }
        }
        return nil
    }

    deinit {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

private struct BubbleOverlayBindingView: View {
    @Bindable var controller: BubbleOverlayController

    var body: some View {
        TimelineView(.animation) { _ in
            BubbleOverlayView(bubbles: controller.bubbles)
        }
    }
}
