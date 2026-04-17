# Design — Audio Recorder

## Overview

Background audio recording with transcription, speaker diarization, translation, and daily summaries. Captures system audio (including Zoom meetings) and microphone input.

## Current Status (Phase 1–6 infrastructure complete)

- ✅ Phase 1: Core recording (mic / system / both modes)
- ✅ Phase 2: Offline transcription via WhisperKit (multi-track support)
- ✅ Phase 3: Real-time transcription wired into recording (per-speaker chunking, crash recovery, rolling summary)
- ✅ Phase 4: Speaker diarization (mock provider; AWS Transcribe stubbed)
- ✅ Phase 5: Voice print matching + translation (mock providers; sherpa-onnx/AWS Translate stubbed)
- ✅ Phase 6: Daily summary (mock provider; Bedrock Claude stubbed)

Phase 4–6 have protocol-based designs with mock implementations. Swap in real AWS/ML providers when ready — no pipeline changes needed.

## Audio Capture Architecture

### Three recording modes

| Mode | Source | Tracks | CLI flag |
|------|--------|--------|----------|
| `mic` | AVAudioEngine microphone input | 1 | `--mic` |
| `system` | ScreenCaptureKit system audio | 1 | `--system` |
| `both` | System + mic as dual tracks | 2 | (default) |

### Dual-track design (both mode)

In "both" mode, system and mic are written as **separate tracks** in one .m4a:
- Track 1: system audio (ScreenCaptureKit) — typically louder (~-18dB mean)
- Track 2: mic (AVAudioEngine) — typically quieter (~-41dB mean)

**Why not mix into single track:** Volume imbalance between system and mic makes naive mixing sound bad. System audio drowns out mic. Proper mixing needs per-source gain control (future enhancement).

**Playback:** Most players (QuickTime, Finder, VLC GUI) only play track 1. Use mpv or the built-in play command:

```bash
charlie-widget record play              # both tracks mixed (system 30% + mic 100%)
charlie-widget record play --mic        # track 2 only
charlie-widget record play --system     # track 1 only

# Or raw mpv with custom volume balance
mpv --lavfi-complex='[aid1]volume=0.3[v1];[aid2]volume=1.0[v2];[v1][v2]amix[ao]' file.m4a
```

### AVAssetWriter implementation details

Both modes use AVAssetWriter for consistent .m4a (AAC) output:
- **Format:** 48kHz mono AAC at 64kbps (macOS AAC encoder rejects 16kHz — must use standard rates)
- **Both mode:** Two AVAssetWriterInputs added BEFORE `startWriting()` (adding after crashes)
- **PTS handling:** Mic uses sample-offset PTS (starts at 0), system uses host-time PTS (starts at ~28000s). Session starts at `.zero` in both mode so both timelines are valid. Single-source modes defer `startSession` to first sample's PTS.

### Permissions

- **Screen Recording (TCC):** Required for ScreenCaptureKit even audio-only. Call `CGRequestScreenCaptureAccess()` at app startup. Embed Info.plist with bundle ID for TCC tracking.
- **Microphone:** Standard AVCaptureDevice permission, prompted automatically.
- Ad-hoc signed debug binaries lose Screen Recording permission on every rebuild. Use `make install` (.app bundle) for stable permission.

## Transcription (Phase 2)

### WhisperKit integration

- **SPM dependency:** `argmax-oss-swift` v0.18.0 — `@preconcurrency import WhisperKit`
- **Model:** `large-v3-v20240930_626MB` (~626MB, downloaded on first use from HuggingFace)
- **Language:** Auto-detect by default. Handles mixed Chinese/English/Japanese well. Optional `--lang` hint for edge cases.
- **Works with CommandLineTools-only** — uses pre-compiled CoreML models, no Xcode needed

### API gotchas

1. **Whisper special tokens leak into text** — `<|startoftranscript|>`, `<|en|>`, `<|0.00|>`. Strip with regex: `<\\|[^|]*\\|>`
2. **Noise markers** — `[BLANK_AUDIO]`, `[Music]`, `[no audio]`, `(music)`, etc. Filtered via regex matching ASCII-only `[...]` and `(...)` patterns. Regex intentionally preserves CJK text inside brackets.
3. **CLI timeout** — Default 5s socket timeout too short. Transcribe uses 600s timeout.
4. **Swift 6 concurrency** — WhisperKit class is not Sendable. Use `@preconcurrency import` and don't add Sendable to TranscriptionEngine.
5. **Model download** — First transcription triggers ~626MB download. Cached at `~/Library/Caches/com.apple.whisperkit/`.

### Multi-track transcription

For `both` mode recordings (dual-track .m4a), each track is extracted to a temporary 16kHz mono WAV via AVAssetReader → AVAudioFile, transcribed separately, and merged by start time. The `speaker` field is set to `"system"` or `"mic"` accordingly. Single-track recordings leave `speaker` as null.

Track extraction: AVAssetReaderTrackOutput reads each track as float32 PCM at 16kHz, AVAudioFile writes the WAV. This avoids AVAssetWriter issues with WAV format settings.

### Output

Transcript saved as `<stem>.transcript` JSON alongside `.m4a`:
```json
{
  "segments": [
    {"start": 0.0, "end": 3.5, "text": "Hello world", "speaker": "system", "language": "en", "translation": null},
    {"start": 1.2, "end": 4.0, "text": "好的没问题", "speaker": "mic", "language": "zh", "translation": null}
  ]
}
```

## Real-time Transcription (Phase 3)

Wired into the recording pipeline: when a recording starts with live transcription enabled, the `AudioCaptureManager.liveAudioCallback` forwards 16kHz mono samples to `TranscriptionEngine.feedAudioBuffer(_:speaker:)`, tagged by source (`"mic"` or `"system"`).

### Per-speaker buffers

Each speaker has its own accumulator inside `TranscriptionEngine.liveBuffers`. The transcription loop transcribes a speaker's buffer when it has ≥ 5 seconds queued. Segments are tagged with the speaker label, preserving dual-track attribution without post-hoc diarization.

### Timestamp accuracy

Chunk start time = `(totalIngestedSamples - chunkLength) / 16000`. Uses cumulative sample count ingested into `feedAudioBuffer`, not wall-clock or `liveSegments.last.end`, so timestamps don't drift under backpressure (slow WhisperKit chunk or UI stalls).

### Memory cap

`liveSegments` is capped at 500 entries in-memory — older segments are trimmed but remain on disk in the `.transcript.partial` file. UI reads `liveSegmentsTail` (last 50).

### Crash recovery

Each committed segment is appended as one JSON line to `{stem}.transcript.partial`. On normal stop, the partial is atomically promoted to `{stem}.transcript` (pretty JSON, matches offline schema) and the partial is deleted. On app launch, `LiveTranscriptWriter.scanAndPromoteOrphans` walks day directories and promotes any `.partial` without a corresponding `.transcript`, logging the count to `RecorderStore.recoveredPartialCount` for the UI banner.

### Language detection

Per-speaker language cache stored in `TranscriptionEngine.lockedLanguages`. When the first chunk of >= 15 seconds is available for a speaker, `WhisperKit.detectLanguage()` is called. If the top language probability exceeds 0.6, that language is locked for the speaker for the remainder of the recording. User overrides from Settings (mic/system language pickers) skip detection entirely and use the chosen language from the start. All locked languages reset on each new recording, since different meetings involve different speakers.

### Toggle

`UserDefaults` key `CharlieWidget.liveTranscription.enabled` (default `true`). Controlled by the Settings toggle. Changes take effect on the next recording — mid-recording toggles are ignored.

### CLI

```bash
charlie-widget record live-transcript            # current liveSegments as JSON
charlie-widget record live-transcript --tail 20  # last N segments
charlie-widget record live-status                # recording + live transcription state
```

## Rolling Summary

While recording, `RollingSummarizer` consumes newly-committed segments via `TranscriptionEngine.onSegmentsCommitted` and flushes a window summary when ALL of these hold:

- A speaker change has occurred since the last flush
- ≥ 90 seconds elapsed since last flush
- ≥ 200 new characters of text accumulated

OR a 5-minute hard ceiling is hit (guards against long monologues).

### Output

`{stem}.live-summary.json` is written atomically on every flush. Schema:

```json
{
  "recordingId": "UUID",
  "runningBullets": ["[00:32] we discussed the migration timeline", "..."],
  "windows": [
    {
      "startOffset": 0.0,
      "endOffset": 142.3,
      "segmentCount": 18,
      "bullets": ["...", "..."],
      "speakersPresent": ["mic", "system"]
    }
  ],
  "lastUpdatedAt": "2026-04-17T14:30:22Z"
}
```

### Providers

Protocol: `WindowSummaryProvider.summarizeWindow(segments:priorRunningBullets:)`.
- `MockWindowSummaryProvider` (current): extracts 2-4 snippets per window, appends 1 running bullet per flush tagged with the window's start offset.
- Future: Bedrock Claude Haiku — same prompt family as `BedrockSummaryProvider.buildPrompt` but window-scoped with prior running bullets as context.

Running bullets are capped at 50 (oldest dropped) so long recordings don't unbounded-grow.

## Pinned Floating Window

NSPanel-based floating window for live transcript, designed to stay visible over all workspaces without stealing focus.

### Window behavior
- NSPanel with `.floating` level, `.nonactivatingPanel` style mask (no focus steal from active app)
- Pin button in RecorderView live transcript header opens the pinned window
- X button = hide (preserves state); does not destroy the window
- Frame position/size and last-visible state persisted to UserDefaults
- Restores automatically on app launch if the window was visible at last quit

### macOS 15 workaround
Minimal `.collectionBehavior = [.canJoinAllSpaces]` to avoid CGS deadlock. Combining `.fullScreenAuxiliary` or `.moveToActiveSpace` with `.utilityWindow` on macOS 15 triggers a Core Graphics Services deadlock during space transitions.

### CLI
```bash
charlie-widget record pin                          # toggle pinned floating window
charlie-widget record pin show                     # show the window
charlie-widget record pin hide                     # hide the window
```

### CLI

```bash
charlie-widget record live-summary               # dump current live summary JSON
```

## Speaker Diarization (Phase 4)

Protocol-based design with swappable providers:

```swift
protocol DiarizationProvider: Sendable {
    func diarize(audioURL: URL, existingSegments: [TranscriptSegment]) async throws -> [TranscriptSegment]
}
```

- **MockDiarizationProvider** (current): Assigns `speaker-0`/`speaker-1` based on inter-segment silence gaps (>1s triggers speaker change). Good enough for two-speaker conversations.
- **AWSTranscribeDiarizationProvider** (stubbed): Upload to S3 → start job → poll → parse speaker labels. Config: region, S3 bucket, max speakers (2–30). ~$0.024/min.

Speaker name mappings stored in `~/Library/Application Support/CharlieWidget/speakers.json` via `SpeakerManager`.

## Voice Print Matching + Translation (Phase 5)

### Voice prints

```swift
protocol VoicePrintProvider: Sendable {
    func extractEmbedding(audioURL: URL, startTime: Double, endTime: Double) async throws -> VoiceEmbedding
    func similarity(_ a: VoiceEmbedding, _ b: VoiceEmbedding) -> Double
}
```

- **MockVoicePrintProvider** (current): Returns deterministic random embeddings per speaker ID
- **Future:** sherpa-onnx + WeSpeaker CAM++ (~50MB, C API, no Python)
- Enrolled profiles at `~/Library/Application Support/CharlieWidget/voiceprints.json`

### Translation

```swift
protocol TranslationProvider: Sendable {
    func translate(text: String, from: String, to: String) async throws -> String
}
```

- **MockTranslationProvider** (current): Returns `"[translated] {text}"`
- **Future:** Amazon Translate ($15/million chars)

### PostProcessingPipeline

Standalone `struct PostProcessingPipeline` runs voice identification → translation in sequence. Takes segments in, returns updated segments out. Does not modify RecorderStore.

## Daily Summary (Phase 6)

```swift
protocol SummaryProvider: Sendable {
    func summarize(transcripts: [(recording: Recording, transcript: Transcript)], date: Date) async throws -> DailySummary
}
```

- **MockSummaryProvider** (current): Extracts highlights from transcript text, lists participants
- **BedrockSummaryProvider** (stubbed): Full prompt template for Claude Haiku defined (groups by meeting, extracts action items, handles multi-language). ~$0.04/day.
- Output: `daily-summary.json` in the day's recording directory

## Voice Command (Hotkey → Transcribe → iTerm)

Press a global hotkey to record a voice command, transcribe it via WhisperKit, and send the text to Claude Code in iTerm.

### Flow
1. **Option+V** (default) → starts mic recording, shows toast
2. **Option+V** again → stops recording → transcribes offline → sends to iTerm via AppleScript
3. Toast shows transcribed text on success

### Architecture
- **HotkeyManager** — Carbon `RegisterEventHotKey` API (no Accessibility permission needed)
- **VoiceCommandService** — state machine (idle → recording → transcribing → idle)
- **VoiceMicRecorder** — lightweight AVAudioEngine → 16kHz mono WAV (WhisperKit-ready, no format conversion needed)
- Uses its own `TranscriptionEngine` instance (separate from RecorderStore)
- Uses its own `AVAudioEngine` (independent of RecorderStore's AudioCaptureManager)

### iTerm integration
AppleScript `write text` sends the transcribed text to iTerm's current session (includes newline, so it submits to Claude Code). Creates a new window if none exists.

### Permissions
- **Microphone** — same as recorder
- **Automation** — macOS prompts on first AppleScript send to iTerm. `NSAppleEventsUsageDescription` in Info.plist provides the dialog text.

### Configuration (Settings tab)
- **Hotkey recorder**: click "⌥V" button → press new shortcut → saved to UserDefaults
- **Enable/disable toggle**: turns hotkey registration on/off
- **Status display**: shows Ready / Recording / Transcribing / Disabled
- Hotkey persisted across restarts via `CharlieWidget.voiceCommand.keyCode/modifiers/enabled`
- **Live transcription language overrides**: separate language picker for mic and system channels
  - Options: Auto-detect / English / Chinese / Japanese / Korean / Spanish / French / German
  - Per-speaker language cache: auto-detected with >60% confidence threshold on ≥15s audio, or user override from Settings
  - Persisted via UserDefaults keys `CharlieWidget.liveTranscription.micLanguage` / `systemLanguage`

### Menu bar indicator
Red dot shows during voice command recording (same indicator as recorder).

## CLI Reference

```bash
# Recording
charlie-widget record start              # start recording (both mode, default)
charlie-widget record start --mic        # mic only
charlie-widget record start --system     # system audio only
charlie-widget record stop               # stop recording
charlie-widget record status             # current state + elapsed + source
charlie-widget record list               # list today's recordings (JSON)

# Playback
charlie-widget record play               # play latest (both tracks mixed via mpv)
charlie-widget record play --mic         # play mic track only
charlie-widget record play --system      # play system track only
charlie-widget record play <id>          # play specific recording

# Management
charlie-widget record delete <id>                  # delete recording + all associated files
charlie-widget record rename <id> <name>           # set a friendly name for a recording

# Processing pipeline
charlie-widget record transcribe <id>              # offline transcription (auto language detect)
charlie-widget record transcribe <id> --lang zh    # with language hint (zh/en/ja/...)
charlie-widget record diarize <id>                 # assign speaker labels (mock: gap-based)
charlie-widget record identify <id>                # voice identification + translation
charlie-widget record summary                      # today's daily summary
charlie-widget record summary --date 2026-04-16    # specific date

# Live state (during recording)
charlie-widget record live-transcript              # current liveSegments as JSON
charlie-widget record live-transcript --tail 20    # last 20 segments only
charlie-widget record live-summary                 # current rolling summary
charlie-widget record live-status                  # isLiveTranscribing, counts, enabled
charlie-widget record pin                          # toggle pinned floating window
charlie-widget record pin show                     # show the window
charlie-widget record pin hide                     # hide the window
```

## Data Storage

Location: `~/Library/Application Support/CharlieWidget/`

```
recordings/2026-04-16/
  recording-143022.m4a                 # Audio (AAC 48kHz mono, or dual-track in both mode)
  recording-143022.json                # Metadata (started_at, ended_at, duration, source, sample_rate)
  recording-143022.transcript          # Transcript JSON (segments with speaker/language/translation)
  recording-143022.transcript.partial  # JSONL live segments during recording (atomically promoted to .transcript on stop)
  recording-143022.live-summary.json   # Rolling summary (running bullets + per-window recaps)
  daily-summary.json                   # Daily summary (after running `record summary`)

speakers.json                    # Speaker name mappings (SpeakerManager)
voiceprints.json                 # Enrolled voice print profiles (VoicePrintStore)
```

## UI

### Recorder tab in dropdown
- **Source picker** (segmented): mic / system / both — only visible when idle
- **Record/Stop button** with red dot indicator
- **Duration timer** (monospaced, secondary color)
- **Audio level meter** — accent color bar, updates in real-time
- **Capture device name** — shows current input device
- **Today's recordings list** — timestamp, duration, source
- **Transcribe button** per recording (or "View" if transcript exists)
- **Inline transcript viewer** — expands below recording, shows timestamp + speaker + text

### Menu bar
- Red dot appears next to "C" icon while recording
- Recording indicator in Recorder tab badge

## Build & Debug

### Build
```bash
swift build --disable-sandbox    # required (sandbox blocks SPM git clone)
```
- First build with WhisperKit: ~2 minutes (290 compilation steps)
- Incremental builds: ~2-3 seconds

### Run
```bash
pkill -f CharlieWidgetApp; .build/debug/CharlieWidgetApp &disown
```

### Debug tips
- **App won't start:** Check `pgrep -f CharlieWidgetApp` — kill old instances first
- **Screen Recording permission lost:** Happens on every rebuild of debug binary. Use `make install` for stable `.app` bundle.
- **Transcription returns empty:** Check cleanText regex — ASCII-only bracket filter. If model isn't loaded, first transcription downloads ~626MB.
- **Socket errors:** Socket at `/tmp/charlie-widget.sock`. If stale, the app removes it on start. If app crashed, manually `rm /tmp/charlie-widget.sock`.
- **IPC timeout:** Transcribe/diarize/identify use 600s timeout. If still timing out, the model may be downloading.
- **Audio level always 0:** Mic permission not granted, or wrong source mode.
- **Both mode: only one track has audio:** System audio requires Screen Recording permission. Mic needs Microphone permission.
- **WhisperKit model cache:** `~/Library/Caches/com.apple.whisperkit/` — delete to force re-download.
- **Console logs:** The app prints `[AudioCapture]`, `[RecorderStore]`, `[TranscriptionEngine]` prefixed logs to stdout.

### Test
```bash
make test-recorder    # or: bash scripts/test-recorder.sh
```
30 assertions covering: start/stop/status/list, metadata persistence, .m4a format verification, double-start rejection, transcription, rename, delete.

### Full pipeline smoke test
```bash
CW=.build/debug/charlie-widget
$CW record start --system           # start system recording
say "Hello test one two three"       # play audio
$CW record stop                      # stop
ID=$($CW record list | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['id'])")
$CW record transcribe $ID           # transcribe
$CW record diarize $ID              # speaker labels
$CW record identify $ID             # voice ID + translate
$CW record summary                   # daily summary
```

## Component Tree

```
Sources/CharlieWidgetApp/Features/Recorder/
  Recording.swift              # Data models (Recording, AudioSource, RecorderState, RecorderError)
  AudioCaptureManager.swift    # ScreenCaptureKit + AVAudioEngine + AVAssetWriter + level metering + live forwarding
  RecorderStore.swift          # @Observable store, recording lifecycle, transcription/diarize/identify/summary dispatch
  TranscriptionEngine.swift    # WhisperKit: offline transcribe, multi-track, live chunked transcription
  RecorderView.swift           # SwiftUI: source picker, record button, level meter, recordings list, transcript viewer
  DiarizationService.swift     # DiarizationProvider protocol + Mock + AWS Transcribe stub
  SpeakerManager.swift         # Speaker ID → display name mapping, persisted JSON
  VoicePrintService.swift      # VoicePrintProvider protocol + Mock + VoicePrintStore (enrollment + identification)
  TranslationService.swift     # TranslationProvider protocol + Mock + AWS Translate stub
  PostProcessingPipeline.swift # Voice identification + translation pipeline (standalone, composable)
  DailySummaryService.swift    # SummaryProvider protocol + Mock + Bedrock Claude stub + DailySummary model
  LiveTranscriptWriter.swift   # JSONL append-only partial writer + orphan recovery
  RollingSummarizer.swift      # Speaker-change+time+chars trigger, WindowSummaryProvider, LiveSummary schema
  LiveTranscriptWindow.swift       # Pinned floating NSPanel controller (frame persistence, show/hide/toggle)
  LiveTranscriptPinnedView.swift   # SwiftUI view for pinned window (auto-scroll, speaker chips, pulse indicator)

Sources/CharlieWidgetApp/Features/VoiceCommand/
  HotkeyManager.swift          # Carbon RegisterEventHotKey wrapper (global hotkey, no Accessibility permission)
  VoiceCommandService.swift    # Hotkey → mic record → WhisperKit transcribe → AppleScript to iTerm

Sources/CharlieWidgetApp/Features/Settings/
  SettingsView.swift           # Settings tab: hotkey recorder, enable/disable toggle, status display
```

## Future Work

- [ ] Connect live transcription UI in RecorderView (DONE — Phase 3)
- [ ] UI buttons for diarize/identify/summary (currently CLI-only)
- [ ] WhisperKit streaming mode (sliding window + token confirmation — fixes chunk-boundary breakage)
- [ ] AWS Transcribe optional backend (for single-track 3+ speaker scenarios)
- [ ] Pyannote / SpeakerKit local diarization (replace mock diarization)
- [ ] VAD-aligned live chunking (currently fixed 5s)
- [ ] Overlap-window chunking (lightweight chunk-boundary fix)
- [ ] Second-pass offline re-transcription after recording for final quality
- [ ] Battery-aware auto-disable of live transcription
- [ ] Real BedrockWindowSummaryProvider (replace mock)
- [ ] Speaker enrollment UI (record voice sample → create profile)
