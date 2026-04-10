import SwiftUI

struct SessionRow: View {
    let session: Session

    var body: some View {
        HStack(spacing: 8) {
            // State indicator
            stateIcon
                .frame(width: 18, height: 18)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    // Agent badge
                    Image(systemName: session.agent.sfSymbol)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)

                    Text(session.projectName)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.head)

                    Spacer()

                    Text(session.state.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text(relativeTime(session.lastUpdated))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var stateIcon: some View {
        switch session.state {
        case .running:
            // Pulsing blue dot for running
            Circle()
                .fill(Color.blue)
                .frame(width: 10, height: 10)
                .shadow(color: .blue.opacity(0.5), radius: 3)
        case .pending:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.orange)
        case .idle:
            Circle()
                .fill(Color.gray.opacity(0.4))
                .frame(width: 10, height: 10)
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 5 { return "just now" }
        if seconds < 60 { return "\(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        return "\(hours)h ago"
    }
}
