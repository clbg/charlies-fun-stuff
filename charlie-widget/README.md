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

# View message history (JSON)
charlie-widget toast --history

# Clear all messages
charlie-widget toast --clear
```

## How it works

- Menu bar shows a bubble icon with unread badge count
- Click icon → dropdown with message history (timestamp, preview, blue dot for unread)
- Click entry → full detail view
- Toast popups appear top-right, auto-dismiss after 3s, click to dismiss
- Multiple toasts stack vertically
- IPC via Unix domain socket (`/tmp/charlie-widget.sock`)
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
