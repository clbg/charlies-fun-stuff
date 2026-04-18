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
# Claude Code / Codex / Gemini hook scripts are installed by `make install`
# View active sessions
charlie-widget sessions

# Clear all session state files
charlie-widget sessions --clear
```

- Menu bar shows colored dots: blue=running, orange=pending, gray=idle
- Click icon → tabbed dropdown: **Sessions** tab (live status) and **Messages** tab (toast history)
- Sessions show project directory, state, and time since last update
- Dead sessions are auto-cleaned via PID detection (+ 5-min TTL fallback)
- Claude Code hooks configured in `~/.claude/settings.json`
- Codex hooks configured via `~/.codex/config.toml` + `~/.codex/hooks.json`
- Gemini hooks configured in `~/.gemini/settings.json`

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

## Audio Recorder

Background audio recording with offline transcription. Captures system audio (including Zoom/Meet), microphone input, or both simultaneously.

```bash
# Recording
charlie-widget record start              # start recording (both system + mic, default)
charlie-widget record start --mic        # mic only
charlie-widget record start --system     # system audio only
charlie-widget record stop               # stop recording
charlie-widget record status             # current state + elapsed time
charlie-widget record list               # list today's recordings (JSON)
charlie-widget record play               # play latest recording
charlie-widget record play --mic         # play mic track only
charlie-widget record play --system      # play system track only
charlie-widget record play <id>          # play specific recording
charlie-widget record delete <id>        # delete recording and all associated files
charlie-widget record rename <id> <name> # set a friendly name

# Live transcription & pinned window
charlie-widget record live-transcript         # current segments (JSON)
charlie-widget record live-transcript --tail 20  # last N segments
charlie-widget record live-summary            # rolling summary (JSON)
charlie-widget record live-status             # live state (flags + counts)
charlie-widget record pin                     # toggle pinned transcript window
charlie-widget record pin show                # show transcript window
charlie-widget record pin hide                # hide transcript window

# Processing pipeline
charlie-widget record transcribe <id>              # transcription (auto language detect)
charlie-widget record transcribe <id> --lang zh    # with language hint
charlie-widget record diarize <id>                 # speaker diarization
charlie-widget record identify <id>                # voice identification + translation
charlie-widget record summary                      # today's daily summary
charlie-widget record summary --date 2026-04-16    # specific date
```

- **Screen Recording permission** required for system audio capture (ScreenCaptureKit). Granted once in System Settings > Privacy.
- **Multi-track:** In both mode, system and mic are written as separate tracks in one .m4a. The `play` command mixes them automatically. Most GUI players only play track 1 — use `record play` or `mpv` for both.
- **Playback** requires [mpv](https://mpv.io/) (`brew install mpv`).
- **Transcription** uses WhisperKit `large-v3` model (~626MB, downloaded on first run). Auto-detects language — handles mixed Chinese/English/Japanese. Language detection is configurable per speaker via the Settings tab. Multi-track recordings are transcribed per-track with speaker labels.
- **Pipeline:** Phase 4–6 (diarization, voice ID, summary) use mock providers. Swap in real AWS/ML implementations when ready.
- Recordings stored at `~/Library/Application Support/CharlieWidget/recordings/YYYY-MM-DD/`
- Recorder tab shows source picker, level meter, today's recordings, and inline transcript viewer
- **Pinned transcript window** floats above other windows for at-a-glance live transcription. Toggle via `record pin [show|hide|toggle]`.

### Settings Tab

The Settings tab (gear icon in the menu bar dropdown) configures recorder and voice command behavior:

- **Voice Command:** hotkey to trigger, enable/disable toggle, multi-CC session target selection
- **Recorder Hotkeys:** per-source hotkey bindings for mic, system audio, and both
- **Transcription:** real-time transcription toggle (default on), per-speaker language override for mic and system channels independently (auto/en/zh/ja/ko/es/fr/de)

See [docs/audio-recorder/design.md](docs/audio-recorder/design.md) for full technical details.

## Bubble Overlay (Screensaver)

A full-screen transparent overlay with floating animated bubbles that reflect the state of your AI coding sessions. Like a Windows screensaver, but driven by real session status.

```bash
charlie-widget bubble on      # enable overlay
charlie-widget bubble off     # disable overlay
charlie-widget bubble status  # show status (JSON: enabled, bubble_count)
```

- **pending** sessions → warm-toned bubble (amber/coral gradient)
- **idle** (done) sessions → cool-toned bubble (cyan/blue gradient)
- **running** sessions → no bubble
- Each bubble shows the agent letter (C/G/X/K) inside
- Bubbles drift and bounce off screen edges
- Bubbles persist until the session state changes (e.g., you approve a pending prompt → running → bubble disappears)
- Max 30 bubbles on screen
- Click a bubble to dismiss it, or move cursor over any bubble to dismiss all
- Dismissed bubbles don't reappear until the session state changes
- Overlay is click-through except on bubbles, appears on all spaces, above normal windows
- On by default, enabled state persists across app restarts

See [docs/cc-monitor/design.md](docs/cc-monitor/design.md) for architecture details.

## Music Cues

Plays ambient music triggered by aggregate session state transitions.

```bash
charlie-widget music on       # enable session music cues
charlie-widget music off      # disable session music cues
charlie-widget music status   # show music status and script path
```

- All sessions idle → plays "calm" music
- Any session pending → plays "tense" music
- Runs external `play-random.sh` script (configurable)
- Enabled by default, persisted to UserDefaults

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

## Hook Setup

`make install` copies these scripts to `~/.local/bin/`:

- `cc-monitor-hook.sh`
- `codex-monitor-hook.sh`
- `gemini-monitor-hook.sh`

The expected state mapping is:

- Claude Code: `UserPromptSubmit` / `PreToolUse` → `running`, `Notification(permission_prompt)` → `pending`, `Stop` → `idle`
- Codex: `SessionStart` → `idle`, `UserPromptSubmit` / `PreToolUse` / `PostToolUse` → `running`, `Stop` → `idle`
- Gemini: `SessionStart` → `idle`, `BeforeAgent` → `running`, `Notification` → `pending`, `AfterAgent` → `idle`, `SessionEnd` → remove session

## Build from source

```bash
make build         # debug build
make release       # release build
make test          # swift test
make test-toast    # send a test toast via CLI
make test-recorder # run recorder integration tests (30 assertions)
make run-app       # run app in debug mode
make clean         # clean build artifacts
```

## Uninstall

```bash
make uninstall
```

This removes the app, CLI, LaunchAgent, and stored messages.
