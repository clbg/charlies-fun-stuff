import AppKit

@MainActor
enum MenuBarIcon {

    /// 2x2 grid positions: top-left=error, top-right=warning, bottom-left=success, bottom-right=info
    private static let gridLayout: [(level: ToastLevel, col: Int, row: Int)] = [
        (.error,   0, 1),  // top-left
        (.warning, 1, 1),  // top-right
        (.success, 0, 0),  // bottom-left
        (.info,    1, 0),  // bottom-right
    ]

    /// A session dot: state determines color, agent determines the letter inside.
    struct SessionDot {
        let state: SessionState
        let agent: AgentKind
    }

    static func make(
        unreadByLevel: [ToastLevel: Int] = [:],
        sessionDots: [SessionDot] = []
    ) -> NSImage {
        let hasUnread = unreadByLevel.values.contains { $0 > 0 }

        let cellSize: CGFloat = 8.0
        let gap: CGFloat = 1.0
        let cornerR: CGFloat = 1.5
        let gridW = cellSize * 2 + gap
        let gridH = cellSize * 2 + gap
        let gridTotalWidth: CGFloat = hasUnread ? gridW + 3 : 0

        // Session dots area — slightly larger to fit letter
        let dotSize: CGFloat = 8.0
        let dotGap: CGFloat = 3.0
        let sessionDotsWidth: CGFloat = sessionDots.isEmpty
            ? 0
            : CGFloat(sessionDots.count) * dotSize + CGFloat(sessionDots.count - 1) * dotGap + 4

        let size = NSSize(width: 50 + gridTotalWidth + sessionDotsWidth, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            // "charlie" text
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: NSColor.black,
            ]
            let str = NSAttributedString(string: "charlie", attributes: attrs)
            let s = str.size()
            str.draw(at: NSPoint(x: (50 - s.width) / 2, y: (rect.height - s.height) / 2))

            // Unread grid (existing)
            if hasUnread {
                let gridX: CGFloat = 52
                let gridY = rect.midY - gridH / 2

                for item in gridLayout {
                    let count = unreadByLevel[item.level] ?? 0
                    let c = item.level.accentColor
                    let x = gridX + CGFloat(item.col) * (cellSize + gap)
                    let y = gridY + CGFloat(item.row) * (cellSize + gap)
                    let cellRect = NSRect(x: x, y: y, width: cellSize, height: cellSize)

                    if count > 0 {
                        let color = NSColor(red: c.red, green: c.green, blue: c.blue, alpha: 1.0)
                        color.setFill()
                        NSBezierPath(roundedRect: cellRect, xRadius: cornerR, yRadius: cornerR).fill()

                        let numAttrs: [NSAttributedString.Key: Any] = [
                            .font: NSFont.monospacedDigitSystemFont(ofSize: 6.5, weight: .heavy),
                            .foregroundColor: NSColor.white,
                        ]
                        let numStr = NSAttributedString(string: count > 9 ? "+" : "\(count)", attributes: numAttrs)
                        let ns = numStr.size()
                        numStr.draw(at: NSPoint(x: x + (cellSize - ns.width) / 2, y: y + (cellSize - ns.height) / 2))
                    } else {
                        NSColor(red: c.red, green: c.green, blue: c.blue, alpha: 0.15).setFill()
                        NSBezierPath(roundedRect: cellRect, xRadius: cornerR, yRadius: cornerR).fill()
                    }
                }
            }

            // Session dots with agent letter
            if !sessionDots.isEmpty {
                var dotX = 50 + gridTotalWidth + 2
                let dotY = rect.midY - dotSize / 2

                for dot in sessionDots {
                    let color: NSColor = switch dot.state {
                    case .running: .systemBlue
                    case .pending: .systemOrange
                    case .idle:    .systemGray.withAlphaComponent(0.4)
                    }

                    color.setFill()
                    let dotRect = NSRect(x: dotX, y: dotY, width: dotSize, height: dotSize)
                    NSBezierPath(roundedRect: dotRect, xRadius: 2, yRadius: 2).fill()

                    // Agent letter
                    let letterAttrs: [NSAttributedString.Key: Any] = [
                        .font: NSFont.monospacedSystemFont(ofSize: 5.5, weight: .bold),
                        .foregroundColor: NSColor.white,
                    ]
                    let letterStr = NSAttributedString(string: dot.agent.dotLetter, attributes: letterAttrs)
                    let ls = letterStr.size()
                    letterStr.draw(at: NSPoint(
                        x: dotX + (dotSize - ls.width) / 2,
                        y: dotY + (dotSize - ls.height) / 2
                    ))

                    dotX += dotSize + dotGap
                }
            }

            return true
        }
        image.isTemplate = false
        return image
    }

    static func makeAppIcon(size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            // Rounded rect yellow background
            let bg = NSBezierPath(roundedRect: rect.insetBy(dx: size * 0.02, dy: size * 0.02),
                                  xRadius: size * 0.22, yRadius: size * 0.22)
            NSColor(red: 1.0, green: 0.85, blue: 0.4, alpha: 1.0).setFill()
            bg.fill()

            let fontSize = size * 0.22
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .heavy),
                .foregroundColor: NSColor(red: 0.2, green: 0.15, blue: 0.1, alpha: 1.0),
            ]
            let str = NSAttributedString(string: "charlie", attributes: attrs)
            let s = str.size()
            str.draw(at: NSPoint(x: (rect.width - s.width) / 2, y: (rect.height - s.height) / 2))
            return true
        }
    }

    static func saveAppIcon(to url: URL) {
        let sizes: [(CGFloat, String)] = [
            (16, "icon_16x16"), (32, "icon_16x16@2x"),
            (32, "icon_32x32"), (64, "icon_32x32@2x"),
            (128, "icon_128x128"), (256, "icon_128x128@2x"),
            (256, "icon_256x256"), (512, "icon_256x256@2x"),
            (512, "icon_512x512"), (1024, "icon_512x512@2x"),
        ]
        let iconsetURL = url.deletingLastPathComponent().appendingPathComponent("CharlieWidget.iconset")
        try? FileManager.default.removeItem(at: iconsetURL)
        try? FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
        for (size, name) in sizes {
            let icon = makeAppIcon(size: size)
            guard let tiff = icon.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { continue }
            try? png.write(to: iconsetURL.appendingPathComponent("\(name).png"))
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        p.arguments = ["-c", "icns", iconsetURL.path, "-o", url.path]
        try? p.run(); p.waitUntilExit()
        try? FileManager.default.removeItem(at: iconsetURL)
    }
}
