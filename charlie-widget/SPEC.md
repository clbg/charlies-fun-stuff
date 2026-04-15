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

Monitors all running AI coding agent sessions (Claude Code, Codex CLI, Gemini CLI) and displays their live status in the menu bar. Uses per-agent hooks to track session state, and PID-based process detection for cleanup.

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
    "agent": "claude | codex | gemini",
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

### Known Limitations
- **"pending" covers both approval wait and execution.** Claude Code has no `ToolApproved` hook event. PreToolUse fires before approval, PostToolUse fires after execution completes. For long-running tools (e.g. Bash), the dot stays orange the entire execution time, not just during the approval wait. If Claude Code adds an intermediate event, use it to transition pending→running at approval time.

### Agent Integration
- Hook script `cc-monitor-hook.sh` reads hook JSON from stdin
- Finds Claude Code process PID by walking ancestor process tree
- Configured in `~/.claude/settings.json` for events:
  - `UserPromptSubmit` → running
  - `PreToolUse` → running (or pending if tool likely needs approval based on permission_mode)
  - `PostToolUse` → running
  - `Stop` → idle
  - `Notification(permission_prompt)` → pending
- Hook script `codex-monitor-hook.sh` reads Codex hook JSON from stdin
- Configured via `~/.codex/config.toml` + `~/.codex/hooks.json` for events:
  - `SessionStart` → idle
  - `UserPromptSubmit` / `PreToolUse` / `PostToolUse` → running
  - `Stop` → idle
- Hook script `gemini-monitor-hook.sh` reads Gemini hook JSON from stdin
- Configured in `~/.gemini/settings.json` for events:
  - `SessionStart` → idle
  - `BeforeAgent` → running
  - `Notification` → pending
  - `AfterAgent` → idle
  - `SessionEnd` → remove session file
- Claude hooks should be `async: true`

### CLI
```bash
charlie-widget sessions              # list active sessions (JSON)
charlie-widget sessions --clear      # remove all session files
```

## Feature 3: Audio Recorder

### What it does

Background audio recording with transcription, speaker diarization, translation, and daily summaries. Captures system audio (including Zoom meetings) and microphone input. Designed for an AWS corporate environment.

### Architecture: Local-First + AWS Cloud

Two-layer approach to minimize cost and maximize privacy:

**Local (on-device, free):**
- Audio capture: ScreenCaptureKit (system/app audio) + AVAudioEngine (mic input)
- Transcription: WhisperKit (CoreML-optimized Whisper, SPM package)
  - `tiny`/`base` model for real-time preview during recording
  - `small`/`medium` model for high-quality offline batch transcription
- Translation: Apple Translation framework (macOS 15+, on-device, EN↔JA)
- Speaker voice identification (V2): sherpa-onnx with WeSpeaker CAM++ (~29 MB ONNX, C API)

**AWS Cloud:**
- Speaker diarization: Amazon Transcribe (built-in, up to 30 speakers, $0.024/min)
- Daily summary: Amazon Bedrock Claude Haiku 4.5 (~$0.04/day)
- Translation fallback: Amazon Translate ($15/million chars) — only if Apple Translation insufficient

### Cost Estimates (8hr/day meetings)
- Local-only + Bedrock summary: ~$0.04/day
- Local + Transcribe diarization: ~$12/day
- Full cloud (Transcribe + Translate + Bedrock): ~$16/day

### Permissions Required
- Screen Recording (TCC) — required for ScreenCaptureKit even audio-only
- Microphone access — for AVAudioEngine mic capture
- No special entitlements (app is not sandboxed)

### Menu Bar Integration
- Record/Stop toggle — click to start/stop background recording
- Recording indicator: red dot when recording
- Recorder status visible in dropdown (new tab or section)

### CLI

```bash
charlie-widget record start              # start recording (system audio + mic)
charlie-widget record start --mic-only   # mic only
charlie-widget record stop               # stop recording
charlie-widget record status             # current recording state + duration
charlie-widget record list               # list today's recordings
charlie-widget record transcribe <id>    # run offline transcription on a recording
charlie-widget record summary            # generate daily summary
charlie-widget record summary --date 2026-04-15  # summary for specific date
```

### Data Storage
- Location: `~/Library/Application Support/CharlieWidget/recordings/`

```
recordings/
  2026-04-15/
    recording-143022.m4a           # Audio (AAC, compressed)
    recording-143022.json          # Metadata
    recording-143022.transcript    # Transcript with timestamps + speakers
    daily-summary.md               # LLM-generated daily summary
```

- Metadata schema:
  ```json
  {
    "id": "uuid",
    "started_at": "ISO-8601",
    "ended_at": "ISO-8601",
    "duration_seconds": 3600,
    "sample_rate": 16000,
    "source": "system+mic",
    "transcription_status": "pending | transcribing | completed",
    "diarization_status": "pending | processing | completed",
    "speakers": [
      {"id": "speaker_0", "label": "Me", "trusted": true},
      {"id": "speaker_1", "label": null, "trusted": false}
    ]
  }
  ```

- Transcript schema:
  ```json
  {
    "segments": [
      {
        "start": 0.0,
        "end": 3.5,
        "text": "Let's start the meeting.",
        "speaker": "speaker_0",
        "language": "en",
        "translation": null
      },
      {
        "start": 3.5,
        "end": 8.2,
        "text": "はい、始めましょう。",
        "speaker": "speaker_1",
        "language": "ja",
        "translation": "Yes, let's begin."
      }
    ]
  }
  ```

### Speaker Management

**MVP (no ML dependencies):**
- Amazon Transcribe provides per-session speaker labels (`spk_0`, `spk_1`, …)
- User manually labels speakers in UI after diarization completes
- App stores speaker→label mappings per meeting
- For recurring meetings, suggest previous labels based on meeting context
- Trusted speakers get highlighted in transcript

**V2 (sherpa-onnx voice prints):**
- sherpa-onnx with WeSpeaker CAM++ model (~29 MB ONNX, C API callable from Swift)
- Extract speaker embeddings per labeled segment, store as voice prints
- On future meetings, auto-match speakers via cosine similarity
- sherpa-onnx has enrollment/search pipeline built in
- Total bundle ~50 MB (runtime + model), no Python needed

### Daily Summary
- Triggered manually (`record summary`) or scheduled (end of day)
- Sends all day's transcripts to Bedrock Claude Haiku 4.5
- Output includes: meeting summaries, key decisions, action items, notable quotes
- Saved as markdown in daily recordings folder

### Implementation Phases
1. **Core Recording** — ScreenCaptureKit + AVAudioEngine, record/stop, save audio files
2. **Local Transcription** — WhisperKit integration, batch transcription after recording
3. **Real-Time Transcription** — Streaming whisper with tiny model during recording
4. **Speaker Diarization** — Amazon Transcribe integration for speaker separation
5. **Trusted Voices + Translation** — MVP: manual speaker labeling in UI + label suggestions for recurring meetings; V2: sherpa-onnx voice prints for auto-matching. Apple Translation for EN↔JA.
6. **Daily Summary** — Bedrock Claude API for end-of-day summarization

### Key Technical Decisions
- Audio format: AAC in .m4a container (smaller than WAV/CAF, adequate for speech)
- Whisper sample rate: 16kHz mono (Whisper's native format)
- Capture strategy: ScreenCaptureKit for system audio (gets Zoom remote participants) + AVAudioEngine for mic (gets your voice) = full meeting coverage
- Heavy Whisper inference runs as subprocess to prevent menu bar app crashes
- Minimum deployment target: macOS 15 (for ScreenCaptureKit audio-only + Translation framework)

### Known Risks
- ScreenCaptureKit/Translation framework availability with CommandLineTools-only SDK (needs verification)
- AWS Connect Voice ID is EOL May 2026 — no AWS-native speaker ID alternative
- V2 speaker ID depends on sherpa-onnx C API stability and WeSpeaker model accuracy for mixed EN/JA speech

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
│   │   │   ├── Sessions/
│   │   │   │   ├── Session.swift       # Data model (AgentKind, SessionState, Session)
│   │   │   │   ├── SessionStore.swift  # FSEvents watcher + PID checking + sweep timer
│   │   │   │   └── SessionRow.swift    # Session row view
│   │   │   └── AudioRecorder/
│   │   │       ├── AudioCaptureManager.swift    # ScreenCaptureKit + AVAudioEngine
│   │   │       ├── RecorderStore.swift          # Recording state management
│   │   │       ├── TranscriptionEngine.swift    # WhisperKit integration
│   │   │       ├── DiarizationService.swift     # Amazon Transcribe integration
│   │   │       ├── TranslationService.swift     # Apple Translation + Amazon Translate
│   │   │       ├── SpeakerStore.swift           # Voice print storage + matching
│   │   │       ├── DailySummaryService.swift    # Bedrock Claude summarization
│   │   │       └── RecorderView.swift           # UI in dropdown
│   │   └── IPC/
│   │       └── SocketServer.swift
│   └── charlie-widget/            # CLI tool
│       └── CLI.swift
├── scripts/
│   ├── cc-monitor-hook.sh         # Claude Code hook script
│   ├── codex-monitor-hook.sh      # Codex hook script
│   └── gemini-monitor-hook.sh     # Gemini hook script
├── docs/
│   ├── toast/
│   │   └── design.md
│   ├── cc-monitor/
│   │   ├── user-stories.md
│   │   └── design.md
│   └── audio-recorder/
│       └── design.md
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

Audio Recorder (Feature 3) is the next major feature under active development.

- Clipboard manager
- Quick notes
- Timer / pomodoro
- System stats
