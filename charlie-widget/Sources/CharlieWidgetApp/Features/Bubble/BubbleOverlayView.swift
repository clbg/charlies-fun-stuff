import SwiftUI

struct BubbleOverlayView: View {

    let bubbles: [Bubble]

    var body: some View {
        ZStack {
            ForEach(bubbles) { bubble in
                BubbleDot(bubble: bubble)
                    .position(bubble.position)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }
}

private struct BubbleDot: View {
    let bubble: Bubble

    private var gradient: RadialGradient {
        let colors: [Color] = bubble.isWarm
            ? [Color(red: 1.0, green: 0.65, blue: 0.0),
               Color(red: 1.0, green: 0.39, blue: 0.28)]
            : [Color(red: 0.0, green: 0.81, blue: 0.82),
               Color(red: 0.25, green: 0.41, blue: 0.88)]
        return RadialGradient(
            colors: colors,
            center: .center,
            startRadius: 0,
            endRadius: bubble.size
        )
    }

    private var glowColor: Color {
        bubble.isWarm
            ? Color(red: 1.0, green: 0.65, blue: 0.0)
            : Color(red: 0.0, green: 0.81, blue: 0.82)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(gradient)
                .frame(width: bubble.size * 2, height: bubble.size * 2)
                .shadow(color: glowColor.opacity(0.6), radius: 10)

            Text(bubble.agentLetter)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
        }
    }
}
