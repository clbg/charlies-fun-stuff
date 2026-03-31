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
- Floating window, top-right corner, semi-transparent dark background
- Shows: title (bold), subtitle (gray), body (main content)
- Auto-dismiss after 3 seconds, click to dismiss immediately
- Multiple toasts stack vertically

### Menu Bar
- Icon in menu bar
- Click → dropdown with message history (timestamp, preview)
- Click entry → full message detail
- "Clear All" at bottom
- Badge count for unread

### CLI

```bash
# Send a toast
charlie-widget toast --title "English Writing Coach" --subtitle "hello how you are" --body "analysis result here"

# Shorthand (title defaults to "Charlie Widget")
charlie-widget toast "some message"

# History
charlie-widget toast --history
charlie-widget toast --clear
```

### Message Persistence
- `~/Library/Application Support/CharlieWidget/messages.json`
- Keep last 100 messages
- Schema: `{ timestamp, title, subtitle, body, read }`

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
2. `make test-toast` — toast pops up, fades after 3s
3. Click menu bar icon — history shows message
4. Send 3 rapid toasts — stack vertically
5. `charlie-widget toast --history` — prints to stdout
6. Kill & restart — history persists
7. Send toast while app not running — app auto-launches

## Future Features (TBD)
- Clipboard manager
- Quick notes
- Timer / pomodoro
- System stats
