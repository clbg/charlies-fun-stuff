import AppKit

/// Floating, non-activating panel right above the subtitle band: as wide as the band, grows upward,
/// shows only the current cue — so the eye can drop straight down to the original line.
/// Drag anywhere to move it, drag an edge to resize; placement is remembered.
@MainActor
final class SubtitleOverlayPanel: NSObject, NSWindowDelegate {
    private let panel: NSPanel
    private let label = NSTextField(wrappingLabelWithString: "")
    private var band: NSRect            // subtitle band, AppKit coords
    private var placedOrigin: NSPoint?  // user placement (bottom-left) — nil = sit on the band
    private var placedWidth: CGFloat?
    private var text = NSAttributedString()
    private let pad: CGFloat = 12
    private let gap: CGFloat = 6
    private let maxHeight: CGFloat = 420

    private var subtitle = ""
    private var explanation = ""
    private var status = ""
    private var isImageRead = false
    private(set) var currentId: Int?

    /// Right-click menu actions (wired by the controller).
    var onClose: (() -> Void)?
    var onPickRegion: (() -> Void)?

    init(band region: CGRect) {
        band = ScreenCoords.toAppKit(region)
        panel = NSPanel(contentRect: NSRect(x: band.minX, y: band.maxY + gap, width: band.width, height: 44),
                        styleMask: [.borderless, .nonactivatingPanel, .resizable], backing: .buffered, defer: false)
        super.init()
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.minSize = NSSize(width: 240, height: 40)
        panel.delegate = self

        // Solid dark background: a blur lets busy video colours bleed through and hurts readability.
        let bg = SubtitleDragView(frame: panel.contentView!.bounds)
        bg.autoresizingMask = [.width, .height]
        bg.wantsLayer = true
        bg.layer?.backgroundColor = NSColor(calibratedWhite: 0.07, alpha: 0.96).cgColor
        bg.layer?.cornerRadius = 12
        bg.layer?.masksToBounds = true
        bg.onDrag = { [weak self] dx, dy in self?.userMove(dx: dx, dy: dy) }
        bg.onDragEnd = { [weak self] in self?.savePlacement() }
        bg.onRightClick = { [weak self] event, view in self?.showMenu(event, in: view) }

        label.isEditable = false
        label.isSelectable = false
        label.drawsBackground = false
        label.isBordered = false
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        bg.addSubview(label)
        panel.contentView = bg

        if let saved = SubtitleStorage.panelPlacement {
            placedOrigin = NSPoint(x: saved.minX, y: saved.minY)
            placedWidth = saved.width
        }
        render()
    }

    func show() { panel.orderFrontRegardless() }
    func close() { panel.orderOut(nil) }

    func setBand(_ region: CGRect) {
        band = ScreenCoords.toAppKit(region)
        render()
    }

    // MARK: Content

    func begin(id: Int, subtitle: String, imageRead: Bool) {
        currentId = id
        self.subtitle = subtitle
        explanation = ""
        status = "…"
        isImageRead = imageRead
        render()
    }

    func setSubtitle(id: Int, _ s: String) { guard id == currentId else { return }; subtitle = s; render() }
    func append(id: Int, _ s: String) { guard id == currentId else { return }; explanation += s; render() }
    func finish(id: Int, status: String) { guard id == currentId else { return }; self.status = status; render() }
    func clear(id: Int) {
        guard id == currentId else { return }
        currentId = nil; subtitle = ""; explanation = ""; status = ""; render()
    }

    func resetPlacement() {
        placedOrigin = nil; placedWidth = nil
        SubtitleStorage.panelPlacement = nil
        render()
    }

    private func render() {
        let out = NSMutableAttributedString()
        if currentId == nil {
            out.append(NSAttributedString(string: "等待字幕…", attributes: [
                .font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.secondaryLabelColor]))
        } else {
            // The original line is right below the panel, so it isn't repeated — except for image reads,
            // where showing what the model read is the point.
            if isImageRead {
                out.append(NSAttributedString(string: subtitle + "\n", attributes: [
                    .font: NSFont.systemFont(ofSize: 20, weight: .semibold), .foregroundColor: NSColor.white]))
            }
            out.append(Self.styled(explanation.trimmingCharacters(in: .whitespacesAndNewlines), size: 17))
            out.append(NSAttributedString(string: "\n" + status + (isImageRead ? "  [图像识别]" : ""), attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor]))
        }
        text = out
        fit()
    }

    /// Minimal markdown: **bold** only.
    private static func styled(_ s: String, size: CGFloat) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for (i, p) in s.components(separatedBy: "**").enumerated() {
            out.append(NSAttributedString(string: p, attributes: [
                .font: i % 2 == 1 ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size),
                .foregroundColor: NSColor.white.withAlphaComponent(0.92)]))
        }
        return out
    }

    // MARK: Right-click menu

    private func showMenu(_ event: NSEvent, in view: NSView) {
        let m = NSMenu()
        m.addItem(MenuAction("关闭字幕讲解") { [weak self] in self?.onClose?() })
        m.addItem(MenuAction("重新框选字幕区域…") { [weak self] in self?.onPickRegion?() })
        m.addItem(MenuAction("讲解框回到字幕上方") { [weak self] in self?.resetPlacement() })
        NSMenu.popUpContextMenu(m, with: event, for: view)
    }

    // MARK: Layout & placement

    /// Size to the text; the bottom edge stays put and longer explanations grow upward.
    private func fit() {
        let width = placedWidth ?? band.width
        let origin = placedOrigin ?? NSPoint(x: band.minX, y: band.maxY + gap)
        let w = width - pad * 2
        label.preferredMaxLayoutWidth = w
        label.attributedStringValue = text
        let textH = ceil(label.cell!.cellSize(forBounds: NSRect(x: 0, y: 0, width: w, height: .greatestFiniteMagnitude)).height)
        let h = min(textH + pad * 2, maxHeight)
        label.frame = NSRect(x: pad, y: pad, width: w, height: h - pad * 2)
        panel.setFrame(NSRect(x: origin.x, y: origin.y, width: width, height: h), display: true)
    }

    private func userMove(dx: CGFloat, dy: CGFloat) {
        let f = panel.frame
        placedOrigin = NSPoint(x: f.minX + dx, y: f.minY + dy)
        placedWidth = f.width
        fit()
    }

    private func savePlacement() {
        guard let o = placedOrigin, let w = placedWidth else { return }
        SubtitleStorage.panelPlacement = NSRect(x: o.x, y: o.y, width: w, height: 0)
    }

    // Native edge resizing (the panel is .resizable): follow it live, remember the result.
    nonisolated func windowDidResize(_ n: Notification) {
        MainActor.assumeIsolated {
            guard panel.inLiveResize else { return }
            placedOrigin = panel.frame.origin
            placedWidth = panel.frame.width
            let w = panel.frame.width - pad * 2
            label.preferredMaxLayoutWidth = w
            label.frame = NSRect(x: pad, y: pad, width: w, height: panel.frame.height - pad * 2)
        }
    }

    nonisolated func windowDidEndLiveResize(_ n: Notification) {
        MainActor.assumeIsolated {
            savePlacement()
            fit()
        }
    }
}

/// Background view: owns all mouse events (the label never takes them) and moves the window on drag.
/// Edge/corner resizing is native window behaviour.
final class SubtitleDragView: NSView {
    var onDrag: ((CGFloat, CGFloat) -> Void)?
    var onDragEnd: (() -> Void)?
    var onRightClick: ((NSEvent, NSView) -> Void)?
    override func rightMouseDown(with e: NSEvent) { onRightClick?(e, self) }
    private var last: NSPoint?

    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with e: NSEvent) { last = NSEvent.mouseLocation }
    override func mouseDragged(with e: NSEvent) {
        guard let l = last else { return }
        let now = NSEvent.mouseLocation
        onDrag?(now.x - l.x, now.y - l.y)
        last = now
    }
    override func mouseUp(with e: NSEvent) { last = nil; onDragEnd?() }
    override func resetCursorRects() { addCursorRect(bounds.insetBy(dx: 6, dy: 6), cursor: .openHand) }
}

/// NSMenuItem that runs a closure.
final class MenuAction: NSMenuItem {
    private let handler: () -> Void
    init(_ title: String, _ handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError("unused") }
    @objc private func run() { handler() }
}

/// Full-screen drag-to-select for the subtitle band.
@MainActor
final class SubtitleRegionPicker {
    private var window: NSWindow?

    func pick(_ completion: @escaping @MainActor (CGRect) -> Void) {
        guard let screen = NSScreen.main else { return }
        let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.level = .screenSaver
        w.isOpaque = false
        w.backgroundColor = NSColor.black.withAlphaComponent(0.25)
        let v = PickView(frame: screen.frame)
        v.onDone = { [weak self] r in
            self?.window?.orderOut(nil)
            self?.window = nil
            if let r {
                completion(ScreenCoords.fromAppKit(NSRect(x: r.minX + screen.frame.minX, y: r.minY + screen.frame.minY,
                                                          width: r.width, height: r.height)))
            }
        }
        w.contentView = v
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w
    }

    private final class PickView: NSView {
        var onDone: ((NSRect?) -> Void)?
        private var start: NSPoint?
        private var rect: NSRect?
        override var acceptsFirstResponder: Bool { true }
        override func draw(_ dirtyRect: NSRect) {
            NSString(string: "拖动框选字幕区域（宽一点，上下留点余量）· Esc 取消")
                .draw(at: NSPoint(x: 40, y: bounds.height - 80),
                      withAttributes: [.font: NSFont.systemFont(ofSize: 24, weight: .bold), .foregroundColor: NSColor.white])
            if let r = rect {
                NSColor.systemYellow.setStroke()
                let p = NSBezierPath(rect: r); p.lineWidth = 3; p.stroke()
            }
        }
        override func viewDidMoveToWindow() { window?.makeFirstResponder(self) }
        override func keyDown(with e: NSEvent) { if e.keyCode == 53 { onDone?(nil) } }
        override func mouseDown(with e: NSEvent) { start = convert(e.locationInWindow, from: nil) }
        override func mouseDragged(with e: NSEvent) {
            guard let s = start else { return }
            let p = convert(e.locationInWindow, from: nil)
            rect = NSRect(x: min(s.x, p.x), y: min(s.y, p.y), width: abs(p.x - s.x), height: abs(p.y - s.y))
            needsDisplay = true
        }
        override func mouseUp(with e: NSEvent) {
            if let r = rect, r.width > 40, r.height > 15 { onDone?(r) }
        }
    }
}
