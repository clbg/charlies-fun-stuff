import SwiftUI
import AppKit

enum DropdownTab: String, CaseIterable {
    case messages = "Messages"
    case sessions = "Sessions"
    case recorder = "Recorder"
}

struct HistoryView: View {

    @Bindable var store: MessageStore
    var sessionStore: SessionStore
    var recorderStore: RecorderStore
    @State private var selectedTab: DropdownTab = .messages
    @State private var selectedMessageID: UUID?
    @State private var copiedMessageID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            tabBar

            Divider()

            // Content
            switch selectedTab {
            case .sessions:
                sessionsTab
            case .messages:
                messagesTab
            case .recorder:
                RecorderView(recorderStore: recorderStore)
            }

            Divider()

            // Footer
            footer
        }
        .frame(width: 340, height: 400)
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(DropdownTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(tab.rawValue)
                            .font(.system(size: 12, weight: selectedTab == tab ? .semibold : .regular))
                        badge(for: tab)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(selectedTab == tab ? Color.accentColor.opacity(0.1) : Color.clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .foregroundStyle(selectedTab == tab ? .primary : .secondary)
            }
        }
    }

    @ViewBuilder
    private func badge(for tab: DropdownTab) -> some View {
        switch tab {
        case .sessions:
            let count = sessionStore.activeSessions.count
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.blue))
            }
        case .messages:
            let count = store.unreadCount
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.red))
            }
        case .recorder:
            if recorderStore.state == .recording {
                Circle()
                    .fill(Color.red)
                    .frame(width: 6, height: 6)
            }
        }
    }

    // MARK: - Sessions Tab

    private var sessionsTab: some View {
        Group {
            if sessionStore.activeSessions.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "terminal")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("No active sessions")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(sessionStore.activeSessions) { session in
                            SessionRow(session: session)
                            Divider()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Messages Tab

    private var messagesTab: some View {
        Group {
            if store.messages.isEmpty {
                emptyPlaceholder
            } else {
                messageList
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    store.muted.toggle()
                } label: {
                    Image(systemName: store.muted ? "bell.slash.fill" : "bell.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(store.muted ? .secondary : .primary)
                }
                .buttonStyle(.plain)
                .help(store.muted ? "Unmute toasts" : "Mute toasts")

                if store.unreadCount > 0 {
                    Text("\(store.unreadCount) unread")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Clear All") {
                    selectedMessageID = nil
                    if selectedTab == .sessions {
                        sessionStore.clearAll()
                    } else {
                        store.clearAll()
                    }
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.red)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            Button {
                openDataFolder()
            } label: {
                HStack {
                    Image(systemName: "folder")
                        .font(.system(size: 11))
                    Text("Open Data Folder...")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Open Data Folder

    private func openDataFolder() {
        let url = SessionStore.sessionsDirectoryURL.deletingLastPathComponent()
        NSWorkspace.shared.open(url)
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
                // Level icon with unread indicator
                ZStack(alignment: .topTrailing) {
                    Image(systemName: message.level.sfSymbol)
                        .font(.system(size: 14))
                        .foregroundStyle(levelColor(message.level))
                        .frame(width: 18, height: 18)

                    if !message.read {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 6, height: 6)
                            .offset(x: 2, y: -2)
                    }
                }
                .padding(.top, 2)

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

                    if let attrStr = try? AttributedString(markdown: message.body, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                        Text(attrStr)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.tail)
                    } else {
                        Text(message.body)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.tail)
                    }
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
                Image(systemName: message.level.sfSymbol)
                    .font(.system(size: 14))
                    .foregroundStyle(levelColor(message.level))
                Text(message.title)
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                Button {
                    copyMessage(message)
                } label: {
                    Image(systemName: copiedMessageID == message.id ? "checkmark.circle.fill" : "doc.on.doc")
                        .foregroundStyle(copiedMessageID == message.id ? .green : .secondary)
                }
                .buttonStyle(.plain)
                .help("Copy message")

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedMessageID = nil
                        store.deleteMessage(id: message.id)
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Delete message")
            }

            if let subtitle = message.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if let attrStr = try? AttributedString(markdown: message.body, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                Text(attrStr)
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(message.body)
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
            }

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

    // MARK: - Actions

    private func copyMessage(_ message: Message) {
        var text = message.title
        if let subtitle = message.subtitle, !subtitle.isEmpty {
            text += "\n\(subtitle)"
        }
        text += "\n\(message.body)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        withAnimation { copiedMessageID = message.id }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation { copiedMessageID = nil }
        }
    }

    // MARK: - Level Color

    private func levelColor(_ level: ToastLevel) -> Color {
        let c = level.accentColor
        return Color(red: c.red, green: c.green, blue: c.blue)
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
