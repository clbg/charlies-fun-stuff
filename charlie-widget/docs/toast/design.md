# Design — Toast Notifications

## Overview

Receives messages from external tools (e.g. Claude Code hooks) and displays floating toast popups. Keeps a history of all messages in the menu bar dropdown.

## Toast Popup

- Floating window, top-right corner, semi-transparent dark background with accent border
- Shows: level icon (colored SF Symbol), title (bold), subtitle (gray), body (markdown-rendered)
- Four levels: `info`, `success`, `warning`, `error` — each with distinct icon and accent color
- Body supports inline markdown: **bold**, *italic*, `code`, [links]
- Panel auto-sizes to fit content (min 280, max 360 wide; max 200 tall)
- Auto-dismiss after 4 seconds, click to dismiss immediately
- Multiple toasts stack vertically (variable height)

## Menu Bar

- Icon in menu bar
- Click → dropdown with message history (level icon, timestamp, markdown preview)
- Click entry → full message detail with markdown rendering
- Click X on expanded entry → delete that message
- "Clear All" at bottom
- Badge count for unread

## CLI

```bash
# Send a toast
charlie-widget toast --title "English Writing Coach" --subtitle "hello how you are" --body "analysis result here"

# Shorthand (title defaults to "Charlie Widget")
charlie-widget toast "some message"

# Toast levels
charlie-widget toast "Build passed" --level success
charlie-widget toast "Deploy failed" --level error
charlie-widget toast "Disk low" --level warning
charlie-widget toast "FYI" --level info    # default

# Inline markdown in body
charlie-widget toast '**All tests** passed in `2.1s`' --level success

# History
charlie-widget toast --history
charlie-widget toast --clear
```

## Message Persistence

- `~/Library/Application Support/CharlieWidget/messages.json`
- Keep last 100 messages
- Schema: `{ timestamp, title, subtitle, body, level, read }`
- Backward compatible: old messages without `level` decode as `info`

## Architecture

- `NSPanel` with `.floating` level for toast windows
- IPC via Unix domain socket (`/tmp/charlie-widget.sock`)
- CLI sends JSON message → SocketServer receives → ToastWindow displays + MessageStore persists

## Component Tree

```
<App>
  MenuBarExtra(icon: MenuBarIcon.make(unread, sessionSummary))
    <HistoryView store={messageStore}>
      Messages tab:
        ForEach(messageStore.messages)
          <MessageRow message={message} />
            → expanded: <MessageDetail />
      Footer:
        Mute | Clear All
```

## Key Decisions

1. **Socket-based IPC.** Toast needs request/response (e.g. history query), so a Unix domain socket is used rather than file-based IPC.

2. **NSPanel over NSWindow.** Floating panel level ensures toasts appear above other windows without stealing focus.

3. **Markdown in body.** Uses `AttributedString(markdown:)` for inline rendering. Supports bold, italic, code, and links.

4. **Level icons with accent colors.** Four levels (info/success/warning/error) each have a distinct SF Symbol and color, providing at-a-glance severity indication.

5. **Auto-sizing panels.** Toast panel width/height adapts to content within min/max bounds, avoiding wasted space for short messages and truncation for long ones.
