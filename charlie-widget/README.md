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
- Any 5 keypresses within 2 seconds dismiss all bubbles (clears the screen while you type)
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

## Sunset Reminder

Daily reminder before sunset, computed locally (NOAA almanac algorithm, no network).

```bash
charlie-widget sunset                    # status: today's sunset time, location, fired events (JSON)
charlie-widget sunset on|off             # enable/disable (default on, persisted)
charlie-widget sunset test               # fire toast + bubble + Bach right now
charlie-widget sunset location 35.68 139.65   # set lat/lon (default Tokyo)
```

- **T-10 min** → warning toast "快日落了" (also saved to Messages; shown even when toasts are muted)
- **T-5 min** → warm 🌇 bubble on the Bubble overlay (shown even if session bubbles are off; disappears at sunset or on hover/click) + 10s of a random `calm_*bach*.wav` from the vault `agent-operator/` audio folder via `afplay -t 10`
- Each event fires once per day; if the Mac was asleep and the event is >2 min late, it's skipped instead of firing late

## Subtitle Tutor

Watches the subtitle band of a video (YouTube CC or burned-in Japanese subtitles), OCRs each new line, and
streams a Chinese translation + grammar notes into a panel floating right above the subtitle.

```bash
charlie-widget subtitle start                          # uses the saved region; first time: drag a box around the subtitles
charlie-widget subtitle start --region 120,790,1130,150 # x,y,w,h in screen points, top-left origin
charlie-widget subtitle stop | toggle | pick | reset-panel | clear-cache | status
```

Or **Settings → Subtitle Tutor** (toggle, re-select region, put the panel back, clear cache) and
**Settings → Model** (preset, provider, model, AWS profile/region or Base URL + API key, latency test).

- Pipeline: ScreenCaptureKit every 200 ms → Apple Vision OCR (`.accurate`, ja; ~40–90 ms) → on a new line,
  cache lookup or a streamed model call (CharlieLLM). If OCR is unsure twice in a row, the frame image is sent to
  the model instead (~3.7 s).
- Non-Japanese lines (player timestamps, logos, Chinese UI text) are dropped: a kept line needs ≥ 1 kana.
- Panel: drag to move, drag an edge to resize; placement is remembered and reset when the region changes.
- Cache: every finished explanation is stored by normalized subtitle text (fuzzy ≥ 0.9). Seeking back or
  rewatching shows it instantly (measured median 94 ms vs ~1.1 s uncached).
- Data: `~/Library/Application Support/CharlieWidget/SubtitleTutor/` (`cache.jsonl`, `logs/session-*.jsonl`);
  region and panel placement in UserDefaults. `CHARLIE_SUBTITLE_HOME` overrides the data dir for tests.
- Default model: Bedrock Tokyo `jp.anthropic.claude-sonnet-4-6` (measured from Tokyo: 534 ms median first
  token vs 633 ms jp Haiku 4.5, 819 ms us Sonnet 5.5; Sonnet 5.5 has no Tokyo profile). Switch in Settings → Model.
- Needs Screen Recording permission (requested on first launch).

Testing (`scripts/subtitle-tutor/`): `synthetic.html` shows 12 timed subtitles over a moving background
(ground truth in `window.__gt`); for YouTube, record the rendered caption DOM (`.caption-visual-line`) with
timestamps. Score a run with `python3 scripts/subtitle-tutor/eval.py <session.jsonl> --gt gt.json`.
`mouse_drag.swift` synthesizes drags for panel move/resize tests.

## LLM providers

`Sources/CharlieLLM` is a small streaming LLM client shared by app features (no third-party deps: Foundation, CryptoKit, Security). Entry point: `LLM.provider(for: LLMConfig) -> any LLMProvider`, then `stream(_:)` yields `.text` deltas and a final `.done(ttftMs:totalMs:)`; cancelling the consuming Task cancels the HTTP request.

| Kind | Endpoint | Auth |
|---|---|---|
| `bedrock` (default) | `bedrock-runtime.{region}.amazonaws.com/model/{id}/invoke-with-response-stream`, AWS event-stream response | SigV4 with creds from `aws configure export-credentials --profile <awsProfile>` (default `claude-code`), cached until 5 min before expiry. Expired → run `mwinit` / ada. |
| `anthropic` | `{baseURL}/v1/messages` (SSE) | Keychain API key |
| `openAICompatible` | `{baseURL}/chat/completions` (SSE), e.g. `https://api.deepseek.com/v1` | Keychain API key (optional) |

- API keys: Keychain generic passwords, service `com.charlie.widget.llm`, account = kind (`LLMKeychain.setAPIKey(_:for:)`). `llm-smoke` also reads `ANTHROPIC_API_KEY` / `OPENAI_API_KEY`.
- Presets for the Settings dropdown: `LLMPresets.all` (us/global Sonnet 5.5, jp Haiku 4.5, us Haiku 5.5, Anthropic API, OpenAI-compatible). Sonnet 5.5 rejects `thinking: disabled` (use `between_tools`); Haiku 4.5 rejects `effort`.
- `aws` is looked up in /opt/homebrew/bin, /usr/local/bin, ~/.local/bin, ~/.aki/bin, ~/.toolbox/bin, then a login shell, since GUI apps get a minimal PATH.
- Debug logs to stderr with `CHARLIE_LLM_DEBUG=1` (never includes credentials or keys).

```bash
swift run -c release llm-smoke --list                                   # presets
swift run -c release llm-smoke --preset bedrock-jp-haiku-4-5 "質問"       # stream text, print ttft/total
swift run -c release llm-smoke --preset bedrock-us-sonnet-5-5 --image sub.png "图里的字幕是什么？"
swift run -c release llm-smoke --preset bedrock-jp-haiku-4-5 --cancel-after-first "1から300まで数えて"
swift run -c release llm-smoke --bench --presets bedrock-jp-haiku-4-5,bedrock-us-sonnet-5-5 --n 6
swift run -c release llm-smoke --selftest                               # offline parser/signer checks
```
(Run `swift run` with `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk` like the Makefile does.)

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
