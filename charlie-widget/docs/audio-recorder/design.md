# Design — Audio Recorder

## Overview

Background audio recording with transcription, speaker diarization, translation, and daily summaries. Captures system audio (including Zoom meetings) and microphone input.

## Current Status (Phase 1–6 infrastructure complete)

- ✅ Phase 1: Core recording (mic / system / both modes)
- ✅ Phase 2: Offline transcription via WhisperKit (multi-track support)
- ✅ Phase 3: Real-time transcription (chunked WhisperKit, 5s buffers)
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

Chunked approach — buffers 5 seconds of 16kHz audio, transcribes each chunk via WhisperKit, appends to `liveSegments`.

- **AudioCaptureManager** forwards audio to `TranscriptionEngine.feedAudioBuffer()` via `liveAudioCallback`
- Resamples from 48kHz to 16kHz using `AVAudioConverter` before forwarding
- Thread-safe buffer using `OSAllocatedUnfairLock`
- `liveSegments`, `livePartialText`, `isLiveTranscribing` are @Observable for UI binding
- Start/stop via `TranscriptionEngine.startLiveTranscription()` / `stopLiveTranscription()`

Note: Live transcription UI in RecorderView is not yet connected — segments are available but not displayed during recording.

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

# Processing pipeline
charlie-widget record transcribe <id>              # offline transcription (auto language detect)
charlie-widget record transcribe <id> --lang zh    # with language hint (zh/en/ja/...)
charlie-widget record diarize <id>                 # assign speaker labels (mock: gap-based)
charlie-widget record identify <id>                # voice identification + translation
charlie-widget record summary                      # today's daily summary
charlie-widget record summary --date 2026-04-16    # specific date
```

## Data Storage

Location: `~/Library/Application Support/CharlieWidget/`

```
recordings/2026-04-16/
  recording-143022.m4a           # Audio (AAC 48kHz mono, or dual-track in both mode)
  recording-143022.json          # Metadata (started_at, ended_at, duration, source, sample_rate)
  recording-143022.transcript    # Transcript JSON (segments with speaker/language/translation)
  daily-summary.json             # Daily summary (after running `record summary`)

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
27 assertions covering: start/stop/status/list, metadata persistence, .m4a format verification, double-start rejection, transcription smoke test.

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
```

## Future Work

- [ ] Connect live transcription UI in RecorderView (data is available, display not wired)
- [ ] UI buttons for diarize/identify/summary (currently CLI-only)
- [ ] Implement real AWS Transcribe provider (replace mock diarization)
- [ ] Implement sherpa-onnx voice print extraction (replace mock embeddings)
- [ ] Implement Amazon Translate provider (replace mock translation)
- [ ] Implement Bedrock Claude summary provider (replace mock summaries)
- [ ] Speaker enrollment UI (record voice sample → create profile)
- [ ] Merge SpeakerManager and VoicePrintStore (overlapping responsibility)
