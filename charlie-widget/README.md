# Charlie Widget

macOS menu bar utility app with floating toast notifications. Receives messages via CLI and displays them as popups.

## Requirements

- macOS 14+
- Swift 6.1+ (CommandLineTools or Xcode)

## Install

```bash
make install    # builds release, installs CLI + App + LaunchAgent
```

This does three things:
- CLI binary → `~/.local/bin/charlie-widget`
- App bundle → `/Applications/CharlieWidget.app` (no Dock icon)
- LaunchAgent → `~/Library/LaunchAgents/com.charlie.widget.plist` (starts on login)

After install, launch with:
```bash
open /Applications/CharlieWidget.app
```
It will auto-start on next login.

## Usage

```bash
# Send a toast (title defaults to "Charlie Widget")
charlie-widget toast "some message"

# Full options
charlie-widget toast --title "Title" --subtitle "Sub" --body "Body text"

# Toast levels: info (default), success, warning, error
charlie-widget toast "Build passed" --level success
charlie-widget toast "Disk full" --level error

# Body supports inline markdown: **bold**, *italic*, `code`
charlie-widget toast '**All tests** passed in `2.1s`' --level success

# View message history (JSON)
charlie-widget toast --history

# Clear all messages
charlie-widget toast --clear
```

## Session Monitoring (CC Monitor)

Tracks all running AI coding agent sessions in the menu bar.

```bash
# Sessions are tracked automatically via Claude Code hooks (installed by `make install`)
# View active sessions
charlie-widget sessions

# Clear all session state files
charlie-widget sessions --clear
```

- Menu bar shows colored dots: blue=running, orange=pending, gray=idle
- Click icon → tabbed dropdown: **Sessions** tab (live status) and **Messages** tab (toast history)
- Sessions show project directory, state, and time since last update
- Dead sessions are auto-cleaned via PID detection (+ 5-min TTL fallback)

### Setup Claude Code hooks

`make install` copies the hook script to `~/.local/bin/cc-monitor-hook.sh`. You still need to add the hooks to `~/.claude/settings.json` once:

```jsonc
// Add these entries under the "hooks" key in ~/.claude/settings.json
// If you already have hooks for these events, add cc-monitor-hook.sh
// alongside your existing hooks.
{
  "hooks": {
    "UserPromptSubmit": [
      { "hooks": [{ "type": "command", "command": "cc-monitor-hook.sh", "async": true }] }
    ],
    "PreToolUse": [
      { "hooks": [{ "type": "command", "command": "cc-monitor-hook.sh", "async": true }] }
    ],
    "Stop": [
      { "hooks": [{ "type": "command", "command": "cc-monitor-hook.sh", "async": true }] }
    ],
    "Notification": [
      {
        "matcher": "permission_prompt",
        "hooks": [{ "type": "command", "command": "cc-monitor-hook.sh", "async": true }]
      }
    ]
  }
}
```

All hooks are `async: true` — they never block the agent. Takes effect immediately for new Claude Code sessions.

## How it works

- Menu bar shows "charlie" text with unread badge grid + session status dots
- Click icon → tabbed dropdown (Sessions | Messages)
- **Sessions tab**: live agent session status, auto-refreshes via FSEvents + 60s sweep timer
- **Messages tab**: toast history (timestamp, preview, blue dot for unread)
- Click message entry → full detail view; click X to delete
- Toast popups appear top-right, auto-dismiss after 4s, click to dismiss
- Toast panel auto-sizes to fit content (min 280, max 360 wide)
- Each toast shows a level icon (info/success/warning/error) with accent color
- Body text renders inline markdown (bold, italic, code, links)
- Multiple toasts stack vertically
- "Open Data Folder..." in footer opens `~/Library/Application Support/CharlieWidget/`
- IPC via Unix domain socket (`/tmp/charlie-widget.sock`) for toasts
- Session state via file-based IPC (`~/Library/Application Support/CharlieWidget/sessions/`)
- Messages persist at `~/Library/Application Support/CharlieWidget/messages.json` (last 100)

## Build from source

```bash
make build      # debug build
make release    # release build
make test       # swift test
make test-toast # send a test toast via CLI
make run-app    # run app in debug mode
make clean      # clean build artifacts
```

## Uninstall

```bash
make uninstall
```

This removes the app, CLI, LaunchAgent, and stored messages.
