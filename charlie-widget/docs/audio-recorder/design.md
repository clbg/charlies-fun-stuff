# Design — Audio Recorder

## Overview

Background audio recording with transcription, speaker diarization, translation, and daily summaries. Captures system audio (including Zoom meetings) and microphone input. Designed for an AWS corporate environment.

## Architecture: Local-First + AWS Cloud

Two-layer approach to minimize cost and maximize privacy:

**Local (on-device, free):**
- Audio capture: ScreenCaptureKit (system/app audio) + AVAudioEngine (mic input)
- Transcription: WhisperKit (CoreML-optimized Whisper, SPM package)
  - `tiny`/`base` model for real-time preview during recording
  - `small`/`medium` model for high-quality offline batch transcription
- Translation: Apple Translation framework (macOS 15+, on-device, EN<>JA)
- Speaker voice identification (V2): sherpa-onnx with WeSpeaker CAM++ (~29 MB ONNX, C API)

**AWS Cloud:**
- Speaker diarization: Amazon Transcribe (built-in, up to 30 speakers, $0.024/min)
- Daily summary: Amazon Bedrock Claude Haiku 4.5 (~$0.04/day)
- Translation fallback: Amazon Translate ($15/million chars) — only if Apple Translation insufficient

## Cost Estimates (8hr/day meetings)

- Local-only + Bedrock summary: ~$0.04/day
- Local + Transcribe diarization: ~$12/day
- Full cloud (Transcribe + Translate + Bedrock): ~$16/day

## Permissions Required

- Screen Recording (TCC) — required for ScreenCaptureKit even audio-only
- Microphone access — for AVAudioEngine mic capture
- No special entitlements (app is not sandboxed)

## Menu Bar Integration

- Record/Stop toggle — click to start/stop background recording
- Recording indicator: red dot when recording
- Recorder status visible in dropdown (new tab or section)

## CLI

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

## Data Storage

Location: `~/Library/Application Support/CharlieWidget/recordings/`

```
recordings/
  2026-04-15/
    recording-143022.m4a           # Audio (AAC, compressed)
    recording-143022.json          # Metadata
    recording-143022.transcript    # Transcript with timestamps + speakers
    daily-summary.md               # LLM-generated daily summary
```

### Metadata Schema

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

### Transcript Schema

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
      "text": "...",
      "speaker": "speaker_1",
      "language": "ja",
      "translation": "Yes, let's begin."
    }
  ]
}
```

## Speaker Management

**MVP (no ML dependencies):**
- Amazon Transcribe provides per-session speaker labels (`spk_0`, `spk_1`, ...)
- User manually labels speakers in UI after diarization completes
- App stores speaker-to-label mappings per meeting
- For recurring meetings, suggest previous labels based on meeting context
- Trusted speakers get highlighted in transcript

**V2 (sherpa-onnx voice prints):**
- sherpa-onnx with WeSpeaker CAM++ model (~29 MB ONNX, C API callable from Swift)
- Extract speaker embeddings per labeled segment, store as voice prints
- On future meetings, auto-match speakers via cosine similarity
- sherpa-onnx has enrollment/search pipeline built in
- Total bundle ~50 MB (runtime + model), no Python needed

## Daily Summary

- Triggered manually (`record summary`) or scheduled (end of day)
- Sends all day's transcripts to Bedrock Claude Haiku 4.5
- Output includes: meeting summaries, key decisions, action items, notable quotes
- Saved as markdown in daily recordings folder

## Implementation Phases

1. **Core Recording** — ScreenCaptureKit + AVAudioEngine, record/stop, save audio files
2. **Local Transcription** — WhisperKit integration, batch transcription after recording
3. **Real-Time Transcription** — Streaming whisper with tiny model during recording
4. **Speaker Diarization** — Amazon Transcribe integration for speaker separation
5. **Trusted Voices + Translation** — MVP: manual speaker labeling in UI + label suggestions for recurring meetings; V2: sherpa-onnx voice prints for auto-matching. Apple Translation for EN<>JA.
6. **Daily Summary** — Bedrock Claude API for end-of-day summarization

## Key Technical Decisions

- Audio format: AAC in .m4a container (smaller than WAV/CAF, adequate for speech)
- Whisper sample rate: 16kHz mono (Whisper's native format)
- Capture strategy: ScreenCaptureKit for system audio (gets Zoom remote participants) + AVAudioEngine for mic (gets your voice) = full meeting coverage
- Heavy Whisper inference runs as subprocess to prevent menu bar app crashes
- Minimum deployment target: macOS 15 (for ScreenCaptureKit audio-only + Translation framework)

## Known Risks

- ScreenCaptureKit/Translation framework availability with CommandLineTools-only SDK (needs verification)
- AWS Connect Voice ID is EOL May 2026 — no AWS-native speaker ID alternative
- V2 speaker ID depends on sherpa-onnx C API stability and WeSpeaker model accuracy for mixed EN/JA speech

## Component Tree

```
Sources/CharlieWidgetApp/Features/AudioRecorder/
  AudioCaptureManager.swift    # ScreenCaptureKit + AVAudioEngine
  RecorderStore.swift          # Recording state management
  TranscriptionEngine.swift    # WhisperKit integration
  DiarizationService.swift     # Amazon Transcribe integration
  TranslationService.swift     # Apple Translation + Amazon Translate
  SpeakerStore.swift           # Voice print storage + matching
  DailySummaryService.swift    # Bedrock Claude summarization
  RecorderView.swift           # UI in dropdown
```
