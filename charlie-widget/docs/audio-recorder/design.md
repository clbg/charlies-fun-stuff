# Design — Audio Recorder

## Overview

Background audio recording with transcription, speaker diarization, translation, and daily summaries. Captures system audio (including Zoom meetings) and microphone input.

## Current Status (Phase 1 + 2 complete)

- ✅ Phase 1: Core recording (mic / system / both modes)
- ✅ Phase 2: Offline transcription via WhisperKit
- ⬜ Phase 3: Real-time transcription
- ⬜ Phase 4: Speaker diarization (Amazon Transcribe)
- ⬜ Phase 5: Trusted voices + translation
- ⬜ Phase 6: Daily summary (Bedrock Claude)

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
- **Model:** `small` (~460MB, downloaded on first use from HuggingFace)
- **Production recommendation:** `large-v3-v20240930_626MB` for Japanese + English
- **Works with CommandLineTools-only** — uses pre-compiled CoreML models, no Xcode needed

### API gotchas

1. **Whisper special tokens leak into text** — `<|startoftranscript|>`, `<|en|>`, `<|0.00|>`. Strip with regex: `<\\|[^|]*\\|>`
2. **Noise markers** — `[BLANK_AUDIO]`, `[Music]`. Filter out for clean transcript.
3. **CLI timeout** — Default 5s socket timeout too short. Transcribe uses 600s timeout.
4. **Swift 6 concurrency** — WhisperKit class is not Sendable. Use `@preconcurrency import` and don't add Sendable to TranscriptionEngine.

### Output

Transcript saved as `<stem>.transcript` JSON alongside `.m4a`:
```json
{
  "segments": [
    {"start": 0.0, "end": 3.5, "text": "Hello world", "speaker": null, "language": "en", "translation": null}
  ]
}
```

## CLI Reference

```bash
charlie-widget record start              # start recording (both mode, default)
charlie-widget record start --mic        # mic only
charlie-widget record start --system     # system audio only
charlie-widget record stop               # stop recording
charlie-widget record status             # current state + elapsed + source
charlie-widget record list               # list today's recordings (JSON)
charlie-widget record play               # play latest (both tracks mixed via mpv)
charlie-widget record play --mic         # play mic track only
charlie-widget record play --system      # play system track only
charlie-widget record play <id>          # play specific recording
charlie-widget record transcribe <id>    # offline transcription (downloads model on first run)
```

## Data Storage

Location: `~/Library/Application Support/CharlieWidget/recordings/YYYY-MM-DD/`

```
recordings/2026-04-16/
  recording-143022.m4a           # Audio (AAC 48kHz mono, or dual-track in both mode)
  recording-143022.json          # Metadata (started_at, ended_at, duration, source)
  recording-143022.transcript    # Transcript JSON (after transcription)
```

## UI

### Recorder tab in dropdown
- **Source picker** (segmented): mic / system / both — only visible when idle
- **Record/Stop button** with red dot indicator
- **Duration timer** (monospaced, secondary color)
- **Audio level meter** — accent color bar, updates in real-time
- **Capture device name** — shows current input device
- **Today's recordings list** — timestamp, duration, source

### Menu bar
- Red dot appears next to "C" icon while recording
- Recording indicator in Recorder tab badge

## Build Notes

- `swift build --disable-sandbox` required when building with WhisperKit dependency from Claude Code (sandbox blocks SPM git clone)
- First build with WhisperKit: ~2 minutes (290 compilation steps for all dependencies)
- Incremental builds: ~2-3 seconds

## Testing

### Integration test script
```bash
make test-recorder    # or: bash scripts/test-recorder.sh
```
25 assertions covering: start/stop/status/list, metadata persistence, .m4a format verification, double-start rejection.

### System audio capture test
```bash
say -o /tmp/test.m4a "Hello test one two three"   # generate test audio
charlie-widget record start                        # start recording
afplay /tmp/test.m4a                               # play through system speakers
charlie-widget record stop                         # stop
charlie-widget record play                         # verify capture
```

## Future Architecture (Phase 3-6)

### AWS cloud services
- Speaker diarization: Amazon Transcribe ($0.024/min, up to 30 speakers)
- Daily summary: Amazon Bedrock Claude Haiku 4.5 (~$0.04/day)
- Translation fallback: Amazon Translate ($15/million chars)

### Speaker management
- **MVP:** Manual labeling in UI after Transcribe diarization
- **V2:** sherpa-onnx + WeSpeaker CAM++ (~50MB, C API, no Python) for auto voice-print matching

## Component Tree

```
Sources/CharlieWidgetApp/Features/Recorder/
  Recording.swift              # Data models (Recording, AudioSource, RecorderState, RecorderError)
  AudioCaptureManager.swift    # ScreenCaptureKit + AVAudioEngine + AVAssetWriter + level metering
  RecorderStore.swift          # @Observable store, recording lifecycle, transcription dispatch
  TranscriptionEngine.swift    # WhisperKit integration + transcript model (TranscriptSegment, Transcript)
  RecorderView.swift           # SwiftUI: source picker, record button, level meter, recordings list
```
