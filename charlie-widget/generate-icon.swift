#!/usr/bin/env swift
import AppKit

func makeIcon(size: CGFloat) -> NSImage {
    NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
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

let iconsetPath = "/tmp/CharlieWidget.iconset"
try? FileManager.default.removeItem(atPath: iconsetPath)
try FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

for (size, name): (CGFloat, String) in [
    (16, "icon_16x16"), (32, "icon_16x16@2x"), (32, "icon_32x32"), (64, "icon_32x32@2x"),
    (128, "icon_128x128"), (256, "icon_128x128@2x"), (256, "icon_256x256"), (512, "icon_256x256@2x"),
    (512, "icon_512x512"), (1024, "icon_512x512@2x"),
] {
    let icon = makeIcon(size: size)
    guard let tiff = icon.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { continue }
    try png.write(to: URL(fileURLWithPath: "\(iconsetPath)/\(name).png"))
}

let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconsetPath, "-o", "/tmp/AppIcon.icns"]
try p.run(); p.waitUntilExit()
try? FileManager.default.removeItem(atPath: iconsetPath)
print("Generated /tmp/AppIcon.icns")
