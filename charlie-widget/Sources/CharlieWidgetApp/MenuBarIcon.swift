import AppKit

@MainActor
enum MenuBarIcon {

    static func make(badgeCount: Int = 0) -> NSImage {
        let size = NSSize(width: 50, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: NSColor.black,
            ]
            let str = NSAttributedString(string: "charlie", attributes: attrs)
            let s = str.size()
            str.draw(at: NSPoint(x: (rect.width - s.width) / 2, y: (rect.height - s.height) / 2))

            if badgeCount > 0 {
                let badgeR: CGFloat = 4.5
                let badgeX = rect.maxX - badgeR + 1
                let badgeY = rect.minY + badgeR - 1
                NSColor.black.setFill()
                NSBezierPath(ovalIn: NSRect(x: badgeX - badgeR, y: badgeY - badgeR, width: badgeR * 2, height: badgeR * 2)).fill()
                let numAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 7, weight: .bold),
                    .foregroundColor: NSColor.white,
                ]
                let numStr = NSAttributedString(string: badgeCount > 9 ? "+" : "\(badgeCount)", attributes: numAttrs)
                let ns = numStr.size()
                numStr.draw(at: NSPoint(x: badgeX - ns.width / 2, y: badgeY - ns.height / 2))
            }
            return true
        }
        image.isTemplate = (badgeCount == 0)
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
