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

## Feature 2: CC Monitor (Session Status)

### What it does

Monitors all running AI coding agent sessions (Claude Code, with future support for Gemini/Codex) and displays their live status in the menu bar. Uses Claude Code hooks to track session state, and PID-based process detection for cleanup.

### Session States
- `running` — agent is actively working (blue dot)
- `idle` — agent finished, waiting for user input (gray dot)
- `pending` — agent needs approval (orange dot)

### Menu Bar
- Colored dots to the right of "charlie" text: blue=running, orange=pending, gray=idle
- Click → dropdown with two tabs: **Sessions** and **Messages**
- Sessions tab shows: state icon, project directory (last 2 path components), relative time
- Badge count on tab shows number of active sessions

### State File Protocol
- Location: `~/Library/Application Support/CharlieWidget/sessions/{session_id}.json`
- Schema:
  ```json
  {
    "session_id": "string",
    "agent": "claude",
    "cwd": "/absolute/path",
    "state": "running | idle | pending",
    "pid": 12345,
    "last_updated": "ISO-8601"
  }
  ```
- Widget watches directory via FSEvents for real-time updates
- PID-based cleanup: `kill(pid, 0)` detects dead processes → auto-remove
- 5-minute TTL fallback for sessions without PID
- 60-second periodic sweep timer catches dead sessions between FSEvents

### Claude Code Integration
- Hook script `cc-monitor-hook.sh` reads hook JSON from stdin
- Finds Claude Code process PID by walking ancestor process tree
- Configured in `~/.claude/settings.json` for events:
  - `UserPromptSubmit` → running
  - `PreToolUse` → running (also resumes from pending)
  - `Stop` → idle
  - `Notification(permission_prompt)` → pending
- All hooks are `async: true` — never block the agent

### CLI
```bash
charlie-widget sessions              # list active sessions (JSON)
charlie-widget sessions --clear      # remove all session files
```

## Project Structure

```
charlie-widget/
├── Package.swift
├── Sources/
│   ├── CharlieWidgetApp/          # Menu bar app
│   │   ├── App.swift              # @main, MenuBarExtra
│   │   ├── MenuBarIcon.swift      # Menu bar icon with unread grid + session dots
│   │   ├── Features/
│   │   │   ├── Toast/
│   │   │   │   ├── ToastWindow.swift
│   │   │   │   ├── HistoryView.swift   # Tabbed dropdown (Sessions | Messages)
│   │   │   │   └── MessageStore.swift
│   │   │   └── Sessions/
│   │   │       ├── Session.swift       # Data model (AgentKind, SessionState, Session)
│   │   │       ├── SessionStore.swift  # FSEvents watcher + PID checking + sweep timer
│   │   │       └── SessionRow.swift    # Session row view
│   │   └── IPC/
│   │       └── SocketServer.swift
│   └── charlie-widget/            # CLI tool
│       └── CLI.swift
├── scripts/
│   └── cc-monitor-hook.sh         # Claude Code hook script
├── docs/cc-monitor/
│   ├── user-stories.md
│   └── design.md
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
