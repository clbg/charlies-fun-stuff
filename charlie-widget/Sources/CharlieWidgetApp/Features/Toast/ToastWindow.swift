import AppKit
import SwiftUI

// MARK: - ToastWindow

@MainActor
final class ToastWindow {

    private static var activeWindows: [NSPanel] = []

    /// Show a floating toast in the top-right corner. Multiple toasts stack vertically.
    static func show(title: String, subtitle: String? = nil, body: String) {
        let index = activeWindows.count
        let panel = makePanel(index: index)

        let content = ToastContentView(
            title: title,
            subtitle: subtitle,
            message: body,
            onDismiss: { [weak panel] in
                guard let panel else { return }
                dismissPanel(panel)
            }
        )

        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = panel.contentView!.bounds
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView?.addSubview(hostingView)

        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            panel.animator().alphaValue = 1
        }

        activeWindows.append(panel)

        // Auto-dismiss after 3 seconds
        let panelRef = panel
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            dismissPanel(panelRef)
        }
    }

    // MARK: - Private

    private static func makePanel(index: Int) -> NSPanel {
        let width: CGFloat = 320
        let height: CGFloat = 100
        let padding: CGFloat = 16
        let spacing: CGFloat = 8

        guard let screen = NSScreen.main else {
            return NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
        }

        let screenFrame = screen.visibleFrame
        let x = screenFrame.maxX - width - padding
        let y = screenFrame.maxY - height - padding - CGFloat(index) * (height + spacing)

        let panel = NSPanel(
            contentRect: NSRect(x: x, y: y, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false

        return panel
    }

    private static func dismissPanel(_ panel: NSPanel) {
        guard activeWindows.contains(where: { $0 === panel }) else { return }

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
            activeWindows.removeAll { $0 === panel }
            repositionWindows()
        })
    }

    private static func repositionWindows() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let width: CGFloat = 320
        let height: CGFloat = 100
        let padding: CGFloat = 16
        let spacing: CGFloat = 8

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            for (i, panel) in activeWindows.enumerated() {
                let x = screenFrame.maxX - width - padding
                let y = screenFrame.maxY - height - padding - CGFloat(i) * (height + spacing)
                panel.animator().setFrame(
                    NSRect(x: x, y: y, width: width, height: height),
                    display: true
                )
            }
        }
    }
}

// MARK: - ToastContentView

private struct ToastContentView: View {
    let title: String
    let subtitle: String?
    let message: String
    let onDismiss: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.gray)
                    .lineLimit(1)
            }

            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.6))
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .onTapGesture {
            onDismiss()
        }
    }
}
