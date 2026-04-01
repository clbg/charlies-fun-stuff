# Charlie Widget - macOS Menu Bar Utility

A personal macOS menu bar utility app. Extensible with multiple features, starting with toast notifications.

## Architecture

- SwiftUI menu bar app (no Dock icon, `LSUIElement = true`)
- Feature-based module structure, each feature is independent
- CLI tool `charlie-widget` for external integration
- IPC via Unix domain socket (`/tmp/charlie-widget.sock`)

## Feature 1: Toast Notifications

### What it does

Receives messages from external tools (e.g. Claude Code hooks) and displays floating toast popups. Keeps a history of all messages in the menu bar dropdown.

### Toast Popup
- Floating window, top-right corner, semi-transparent dark background with accent border
- Shows: level icon (colored SF Symbol), title (bold), subtitle (gray), body (markdown-rendered)
- Four levels: `info`, `success`, `warning`, `error` — each with distinct icon and accent color
- Body supports inline markdown: **bold**, *italic*, `code`, [links]
- Panel auto-sizes to fit content (min 280, max 360 wide; max 200 tall)
- Auto-dismiss after 4 seconds, click to dismiss immediately
- Multiple toasts stack vertically (variable height)

### Menu Bar
- Icon in menu bar
- Click → dropdown with message history (level icon, timestamp, markdown preview)
- Click entry → full message detail with markdown rendering
- Click X on expanded entry → delete that message
- "Clear All" at bottom
- Badge count for unread

### CLI

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

### Message Persistence
- `~/Library/Application Support/CharlieWidget/messages.json`
- Keep last 100 messages
- Schema: `{ timestamp, title, subtitle, body, level, read }`
- Backward compatible: old messages without `level` decode as `info`

## Project Structure

```
charlie-widget/
├── Package.swift
├── Sources/
│   ├── CharlieWidgetApp/          # Menu bar app
│   │   ├── App.swift              # @main, MenuBarExtra
│   │   ├── Features/
│   │   │   └── Toast/
│   │   │       ├── ToastWindow.swift
│   │   │       ├── HistoryView.swift
│   │   │       └── MessageStore.swift
│   │   └── IPC/
│   │       └── SocketServer.swift
│   └── charlie-widget/            # CLI tool
│       └── CLI.swift
├── Makefile
├── SPEC.md
└── README.md
```

## Tech Stack

- Swift 6, SwiftUI, macOS 14+
- Pure SPM (no Xcode project)
- `NSPanel` with `.floating` level for toast windows
- `MenuBarExtra` for menu bar presence
- Unix domain socket for IPC

## Build & Test

```bash
make build          # swift build
make release        # swift build -c release
make install        # CLI → ~/.local/bin, App → /Applications
make run-app        # swift run CharlieWidgetApp
make test-toast     # send a test toast via CLI
make test           # swift test
make clean          # swift package clean
```

### Manual Testing Checklist
1. `make run-app` — icon appears in menu bar
2. `make test-toast` — toast pops up with icon, fades after 4s
3. Send toasts with each `--level` — correct icon and color
4. Send toast with markdown body — bold/italic/code rendered
5. Send short and long messages — panel auto-sizes
6. Click menu bar icon — history shows level icons and markdown
7. Click entry → expand detail; click X → message deleted
8. Send 3 rapid toasts — stack vertically with variable heights
9. `charlie-widget toast --history` — JSON includes `level` field
10. Kill & restart — history persists, old messages without `level` load as info
11. Send toast while app not running — app auto-launches

## Future Features (TBD)
- Clipboard manager
- Quick notes
- Timer / pomodoro
- System stats
