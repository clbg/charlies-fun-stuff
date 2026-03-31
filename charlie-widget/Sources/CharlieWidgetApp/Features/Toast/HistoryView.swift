import SwiftUI

struct HistoryView: View {

    @Bindable var store: MessageStore
    @State private var selectedMessageID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            if store.messages.isEmpty {
                emptyPlaceholder
            } else {
                messageList
            }

            Divider()

            HStack {
                if store.unreadCount > 0 {
                    Text("\(store.unreadCount) unread")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Clear All") {
                    selectedMessageID = nil
                    store.clearAll()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.red)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 340, height: 400)
    }

    // MARK: - Subviews

    private var emptyPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("No messages")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var messageList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(store.messages) { message in
                    if selectedMessageID == message.id {
                        detailRow(message)
                    } else {
                        summaryRow(message)
                    }
                    Divider()
                }
            }
        }
    }

    private func summaryRow(_ message: Message) -> some View {
        Button {
            store.markAsRead(id: message.id)
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedMessageID = (selectedMessageID == message.id) ? nil : message.id
            }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                // Unread indicator
                Circle()
                    .fill(message.read ? Color.clear : Color.blue)
                    .frame(width: 8, height: 8)
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(message.title)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                        Spacer()
                        Text(relativeTime(message.timestamp))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Text(message.body)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func detailRow(_ message: Message) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(message.title)
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedMessageID = nil
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if let subtitle = message.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Text(message.body)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)

            Text(fullTimestamp(message.timestamp))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.06))
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedMessageID = nil
            }
        }
    }

    // MARK: - Time Formatting

    private func relativeTime(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 5 { return "now" }
        if seconds < 60 { return "\(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        let days = hours / 24
        return "\(days)d ago"
    }

    private func fullTimestamp(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .standard)
    }
}
