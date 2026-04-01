import AppKit
import SwiftUI

// MARK: - ToastWindow

@MainActor
final class ToastWindow {

    private static var activeWindows: [NSPanel] = []

    private static let maxWidth: CGFloat = 360
    private static let minWidth: CGFloat = 280
    private static let maxHeight: CGFloat = 200
    private static let padding: CGFloat = 16
    private static let spacing: CGFloat = 8

    /// Show a floating toast in the top-right corner. Multiple toasts stack vertically.
    static func show(title: String, subtitle: String? = nil, body: String, level: ToastLevel = .info) {
        // Use a mutable box so we can wire up the dismiss closure after panel creation
        let dismissBox = DismissBox()

        let content = ToastContentView(
            title: title,
            subtitle: subtitle,
            message: body,
            level: level,
            onDismiss: { dismissBox.action() }
        )

        let hostingView = NSHostingView(rootView: content)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        let fittingSize = hostingView.fittingSize
        let width = min(max(fittingSize.width, minWidth), maxWidth)
        let height = min(fittingSize.height, maxHeight)

        let panel = makePanel(width: width, height: height)

        dismissBox.action = { [weak panel] in
            guard let panel else { return }
            dismissPanel(panel)
        }

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

        // Auto-dismiss after 4 seconds (slightly longer for richer content)
        let panelRef = panel
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            dismissPanel(panelRef)
        }
    }

    // MARK: - Private

    private static func makePanel(width: CGFloat, height: CGFloat) -> NSPanel {
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

        // Stack below existing toasts
        var yOffset: CGFloat = padding
        for existingPanel in activeWindows {
            yOffset += existingPanel.frame.height + spacing
        }
        let y = screenFrame.maxY - height - yOffset

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

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            var yOffset: CGFloat = padding
            for panel in activeWindows {
                let width = panel.frame.width
                let height = panel.frame.height
                let x = screenFrame.maxX - width - padding
                let y = screenFrame.maxY - height - yOffset
                panel.animator().setFrame(
                    NSRect(x: x, y: y, width: width, height: height),
                    display: true
                )
                yOffset += height + spacing
            }
        }
    }
}

// MARK: - DismissBox

@MainActor
private final class DismissBox {
    var action: @MainActor () -> Void = {}
}

// MARK: - ToastContentView

private struct ToastContentView: View {
    let title: String
    let subtitle: String?
    let message: String
    let level: ToastLevel
    let onDismiss: @MainActor () -> Void

    private var levelColor: Color {
        let c = level.accentColor
        return Color(red: c.red, green: c.green, blue: c.blue)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Level icon
            Image(systemName: level.sfSymbol)
                .font(.system(size: 20))
                .foregroundStyle(levelColor)
                .frame(width: 24, height: 24)
                .padding(.top, 1)

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

                // Markdown-rendered body
                if let attrStr = try? AttributedString(markdown: message, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                    Text(attrStr)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(5)
                        .tint(levelColor)
                } else {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(5)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
        .overlay(
            // Subtle accent bar on the leading edge
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    LinearGradient(
                        colors: [levelColor.opacity(0.6), levelColor.opacity(0.1)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .onTapGesture {
            onDismiss()
        }
    }
}
