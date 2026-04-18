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

### Agent Integration
- Hook script `cc-monitor-hook.sh` reads hook JSON from stdin
- Finds Claude Code process PID by walking ancestor process tree
- Configured in `~/.claude/settings.json` for events:
  - `UserPromptSubmit` → running
  - `PreToolUse` → running
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

Background audio recording with real-time transcription, speaker diarization, translation, and daily summaries. Captures system audio (including Zoom meetings) and microphone input. All six implementation phases are complete.

### Architecture: Local-First + AWS Cloud

Two-layer approach to minimize cost and maximize privacy:

**Local (on-device, free):**
- Audio capture: ScreenCaptureKit (system/app audio) + AVAudioEngine (mic input)
- Transcription: WhisperKit (CoreML-optimized Whisper, SPM package)
  - Real-time streaming transcription during recording (per-speaker chunking)
  - Offline batch transcription for high-quality post-recording results
- Translation: Apple Translation framework (macOS 15+, on-device, EN↔JA)
- Speaker voice identification: sherpa-onnx with WeSpeaker CAM++ (~29 MB ONNX, C API)

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
- Global hotkey for record toggle (`RecorderHotkeyService`)

### CLI

```bash
# Recording lifecycle
charlie-widget record start              # start recording (system audio + mic)
charlie-widget record start --mic        # mic only
charlie-widget record start --system     # system audio only
charlie-widget record stop               # stop recording
charlie-widget record status             # current recording state + duration
charlie-widget record list               # list today's recordings

# Playback
charlie-widget record play               # play latest (both tracks mixed)
charlie-widget record play --mic         # play mic track only
charlie-widget record play --system      # play system track only
charlie-widget record play <id>          # play specific recording

# Management
charlie-widget record delete <id>        # delete a recording and all its files
charlie-widget record rename <id> <name> # rename a recording

# Post-processing pipeline
charlie-widget record transcribe <id>              # offline transcription
charlie-widget record transcribe <id> --lang zh    # with language hint
charlie-widget record diarize <id>                 # assign speaker labels
charlie-widget record identify <id>                # voice identification + translation
charlie-widget record summary                      # generate today's daily summary
charlie-widget record summary --date 2026-04-15    # summary for specific date

# Live session (during active recording)
charlie-widget record live-transcript              # current live transcript segments (JSON)
charlie-widget record live-transcript --tail 20    # last N segments only
charlie-widget record live-summary                 # current rolling summary (JSON)
charlie-widget record live-status                  # live state (flags + counts)
charlie-widget record pin [show|hide|toggle]       # toggle pinned floating transcript window
```

### Data Storage
- Location: `~/Library/Application Support/CharlieWidget/recordings/`

```
recordings/
  2026-04-15/
    recording-143022.m4a                 # Audio (AAC, compressed)
    recording-143022.json                # Metadata
    recording-143022.transcript          # Transcript with timestamps + speakers
    recording-143022.transcript.partial  # JSONL crash recovery (promoted to .transcript on stop)
    recording-143022.live-summary.json   # Rolling summary generated during recording
    daily-summary.json                   # LLM-generated daily summary
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

### Real-Time Transcription
- Wired into the recording pipeline with per-speaker chunking
- Crash recovery: `.transcript.partial` (JSONL) written during recording, atomically promoted to `.transcript` on clean stop; orphaned partials recovered on next launch (`LiveTranscriptWriter`)
- Rolling summarizer triggered by speaker changes, time gaps, and character thresholds (`RollingSummarizer`)
- Per-speaker language detection cache with Settings override
- Pinned floating NSPanel (`LiveTranscriptWindow`) shows live transcript during recording

### Speaker Management

**MVP (implemented):**
- Amazon Transcribe provides per-session speaker labels (`spk_0`, `spk_1`, …)
- User manually labels speakers in UI after diarization completes
- App stores speaker→label mappings per meeting
- For recurring meetings, suggest previous labels based on meeting context
- Trusted speakers get highlighted in transcript

**V2 (implemented — sherpa-onnx voice prints):**
- sherpa-onnx with WeSpeaker CAM++ model (~29 MB ONNX, C API callable from Swift)
- Extract speaker embeddings per labeled segment, store as voice prints
- On future meetings, auto-match speakers via cosine similarity
- sherpa-onnx has enrollment/search pipeline built in
- Total bundle ~50 MB (runtime + model), no Python needed

### Daily Summary
- Triggered manually (`record summary`) or scheduled (end of day)
- Sends all day's transcripts to Bedrock Claude Haiku 4.5
- Output includes: meeting summaries, key decisions, action items, notable quotes
- Saved as JSON in daily recordings folder

### Implementation Phases (all complete)
1. **Core Recording** (done) — ScreenCaptureKit + AVAudioEngine, record/stop, save audio files
2. **Local Transcription** (done) — WhisperKit integration, batch transcription after recording
3. **Real-Time Transcription** (done) — Streaming whisper during recording with per-speaker chunking, crash recovery, rolling summarizer, pinned transcript window
4. **Speaker Diarization** (done) — Amazon Transcribe integration for speaker separation
5. **Trusted Voices + Translation** (done) — Manual speaker labeling in UI + label suggestions for recurring meetings; sherpa-onnx voice prints for auto-matching. Apple Translation for EN↔JA. Per-speaker language detection cache.
6. **Daily Summary** (done) — Bedrock Claude API for end-of-day summarization

### Key Technical Decisions
- Audio format: AAC in .m4a container (smaller than WAV/CAF, adequate for speech)
- Whisper sample rate: 16kHz mono (Whisper's native format)
- Capture strategy: ScreenCaptureKit for system audio (gets Zoom remote participants) + AVAudioEngine for mic (gets your voice) = full meeting coverage
- Heavy Whisper inference runs as subprocess to prevent menu bar app crashes
- Minimum deployment target: macOS 15 (for ScreenCaptureKit audio-only + Translation framework)

### Known Risks
- ScreenCaptureKit/Translation framework availability with CommandLineTools-only SDK (needs verification)
- V2 speaker ID depends on sherpa-onnx C API stability and WeSpeaker model accuracy for mixed EN/JA speech

## Feature 4: Bubble Overlay (Screensaver)

### What it does

A full-screen transparent overlay that shows floating animated bubbles reflecting the state of AI coding sessions. Pending sessions produce warm-toned (amber/coral) bubbles; idle/done sessions produce cool-toned (cyan/blue) bubbles. Running sessions produce no bubbles.

### Behavior
- Bubbles are **state-driven, not event-driven** — each pending/idle session has exactly one bubble on screen
- Bubbles persist until the session transitions to `running` or disappears
- Each bubble drifts randomly, bounces off screen edges, and shows the agent letter (C/G/X/K) inside
- Max 12 bubbles on screen; oldest removed when cap hit
- Click a bubble to dismiss it (dismissed bubbles don't reappear until session state changes)
- Overlay window: borderless, transparent, click-through except on bubbles (custom `hitTest`), `.floating` level, all spaces
- On by default, toggled via CLI

### CLI

```bash
charlie-widget bubble on      # enable overlay
charlie-widget bubble off     # disable overlay
charlie-widget bubble status  # JSON: {"enabled": true, "bubble_count": 2}
```

### Architecture

- `BubbleModel` — keyed by session ID, stores position/velocity/size/warmth
- `BubbleOverlayView` — SwiftUI view using `TimelineView(.animation)` for 60fps rendering
- `BubbleOverlayController` — `@Observable` controller, observes `SessionStore` every 500ms, syncs bubbles to session states (pending→warm, idle→cool, running→remove)
- Window managed by controller: full-screen NSWindow, click-through, all spaces
- Socket commands: `bubble_on`, `bubble_off`, `bubble_status`

### Design Decisions

1. **State-driven, not event-driven.** Bubbles map 1:1 to sessions in pending/idle state. When you approve a prompt (pending→running), the bubble disappears immediately. No manual cleanup needed.
2. **No auto-fade.** Bubbles persist as long as the session state warrants them. The user should act on pending prompts, not wait for them to disappear.
3. **Click-through with hit testing.** The overlay uses a custom `NSWindow` subclass with `hitTest` that only responds to clicks within bubble radii. Clicking empty space passes through to windows underneath. Dismissed bubbles are tracked in `dismissedIds` and don't reappear until the session transitions to a different state.

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
│   │   │   ├── Bubble/
│   │   │   │   ├── BubbleModel.swift          # Data model (keyed by session ID)
│   │   │   │   ├── BubbleOverlayView.swift    # SwiftUI animated view (TimelineView)
│   │   │   │   └── BubbleOverlayWindow.swift  # Controller + NSWindow management
│   │   │   ├── Recorder/
│   │   │   │   ├── AudioCaptureManager.swift    # ScreenCaptureKit + AVAudioEngine
│   │   │   │   ├── RecorderStore.swift          # Recording state management
│   │   │   │   ├── Recording.swift              # Recording data model
│   │   │   │   ├── RecorderView.swift           # UI in dropdown
│   │   │   │   ├── RecorderHotkeyService.swift  # Global hotkey for record toggle
│   │   │   │   ├── TranscriptionEngine.swift    # WhisperKit integration
│   │   │   │   ├── DiarizationService.swift     # Amazon Transcribe integration
│   │   │   │   ├── TranslationService.swift     # Apple Translation + Amazon Translate
│   │   │   │   ├── SpeakerManager.swift         # Speaker label management
│   │   │   │   ├── VoicePrintService.swift      # Voice print storage + matching
│   │   │   │   ├── DailySummaryService.swift    # Bedrock Claude summarization
│   │   │   │   ├── PostProcessingPipeline.swift # Post-diarization pipeline
│   │   │   │   ├── RollingSummarizer.swift      # Rolling summary during recording
│   │   │   │   ├── LiveTranscriptWindow.swift   # Pinned transcript window controller
│   │   │   │   ├── LiveTranscriptPinnedView.swift # SwiftUI view for pinned window
│   │   │   │   └── LiveTranscriptWriter.swift   # Partial transcript file + orphan recovery
│   │   │   ├── VoiceCommand/
│   │   │   │   ├── HotkeyManager.swift          # Global hotkey registration
│   │   │   │   └── VoiceCommandService.swift    # Voice-to-text → iTerm
│   │   │   └── Settings/
│   │   │       └── SettingsView.swift           # Settings tab UI
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

- Clipboard manager
- Quick notes
- Timer / pomodoro
- System stats
