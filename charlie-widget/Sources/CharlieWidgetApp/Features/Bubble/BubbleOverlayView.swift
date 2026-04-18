import SwiftUI
import AppKit

private struct FrostedCircle: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true

        let effect = NSVisualEffectView()
        effect.material = material
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(effect)

        let effect2 = NSVisualEffectView()
        effect2.material = material
        effect2.blendingMode = .behindWindow
        effect2.state = .active
        effect2.wantsLayer = true
        effect2.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(effect2)

        NSLayoutConstraint.activate([
            effect.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            effect.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            effect.topAnchor.constraint(equalTo: container.topAnchor),
            effect.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            effect2.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            effect2.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            effect2.topAnchor.constraint(equalTo: container.topAnchor),
            effect2.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        container.layer?.cornerRadius = 10000
        container.layer?.masksToBounds = true
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.layer?.cornerRadius = nsView.bounds.width / 2
    }
}

struct BubbleOverlayView: View {

    let bubbles: [Bubble]

    var body: some View {
        GeometryReader { geometry in
            ForEach(bubbles) { bubble in
                BubbleDot(bubble: bubble)
                    .position(x: bubble.position.x,
                              y: geometry.size.height - bubble.position.y)
            }
        }
        .background(Color.clear)
    }
}

private struct BubbleDot: View {
    let bubble: Bubble

    private var rimColor: Color {
        bubble.isWarm
            ? Color(hue: 0.08, saturation: 0.40, brightness: 0.88)
            : Color(hue: 0.55, saturation: 0.35, brightness: 0.82)
    }

    private var glowColor: Color {
        bubble.isWarm
            ? Color(hue: 0.08, saturation: 0.45, brightness: 0.92)
            : Color(hue: 0.55, saturation: 0.40, brightness: 0.87)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [glowColor.opacity(0.3), .clear],
                        center: .center,
                        startRadius: bubble.size * 0.6,
                        endRadius: bubble.size * 1.2
                    )
                )
                .frame(width: bubble.size * 2.4, height: bubble.size * 2.4)

            FrostedCircle(material: .fullScreenUI)
                .opacity(0.45)
                .overlay(Circle().fill(rimColor.opacity(0.08)))
                .clipShape(Circle())
                .frame(width: bubble.size * 2, height: bubble.size * 2)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [.clear, .clear, rimColor.opacity(0.35)],
                        center: .center,
                        startRadius: bubble.size * 0.5,
                        endRadius: bubble.size
                    )
                )
                .frame(width: bubble.size * 2, height: bubble.size * 2)

            Text(bubble.agentLetter)
                .font(.system(size: 22, weight: .semibold, design: .monospaced))
                .foregroundStyle(rimColor.opacity(0.8))
        }
    }
}
