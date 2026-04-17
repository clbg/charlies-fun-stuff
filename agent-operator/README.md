# AgentOperator

macOS menu-bar client for a voice-telephone agent system. Speak into your mic (or phone) and Claude answers.

## Architecture

Two modes:

**Mode A — Direct mic (Phase 0, working)**
```
Mac mic → MicCapture (AVAudioEngine, 16kHz)
              → SpeechRecognizer (WhisperKit large-v3)
                   → ClaudeClient (claude --bare -p)
                        → terminal / menu bar
```

**Mode B — SIP phone (Phase 1, infrastructure ready)**
```
Phone/Softphone → FreeSWITCH (PBX, records WAV)
                      → ESLClient (Event Socket, TCP 8021)
                           → WAVReader → SpeechRecognizer → ClaudeClient
```

## Components

| File | Role |
|------|------|
| `App.swift` | Menu bar UI, --listen CLI mode, setup |
| `HotkeyManager.swift` | Global Option+L hotkey (Carbon API) |
| `AppState.swift` | Observable state: status, duration, Q&A history |
| `ListenService.swift` | Orchestrates mic → STT → Claude cycle |
| `MicCapture.swift` | AVAudioEngine mic capture, 48→16kHz resample |
| `MicPipeline.swift` | CLI smoke test pipeline |
| `SpeechRecognizer.swift` | WhisperKit large-v3, local model cache |
| `ClaudeClient.swift` | `claude --bare -p` subprocess |
| `ESLClient.swift` | FreeSWITCH ESL TCP client |
| `CallPipeline.swift` | SIP call → WAV → STT → Claude |
| `WAVReader.swift` | AVAudioFile → 16kHz float32 |
| `RTPListener.swift` | UDP μ-law receiver (kept for future direct RTP) |
| `ULawCodec.swift` | G.711 μ-law decode table |

## Requirements

- macOS 14+
- Swift 6.1+
- `claude` CLI in `~/.local/bin/`
- WhisperKit model cached at `~/Documents/huggingface/models/argmaxinc/whisperkit-coreml/openai_whisper-large-v3-v20240930_626MB/`
- FreeSWITCH (`brew install freeswitch`) — for SIP mode
- baresip (`brew install baresip`) — CLI softphone for testing

## Quick Start (Direct mic)

```bash
make build
# CLI mode:
swift run AgentOperatorApp --listen --seconds 8
# Or install menu bar app:
make install
# Then press Option+L to listen
```

## Quick Start (SIP)

```bash
# 1. Start FreeSWITCH
make sip-up

# 2. Run app
swift run AgentOperatorApp

# 3. Register softphone
#    baresip or Linphone → 127.0.0.1:5060
#    User: 1001, Password: 1234

# 4. Dial 6000, speak, hang up → see Claude response
```

## Makefile Targets

```bash
make build         # debug build
make release       # release build
make install       # release + CLI + App bundle + LaunchAgent
make run-app       # run app in debug
make test-hello    # CLI sanity check
make test          # swift test
make clean         # clean build
make uninstall     # remove everything
make sip-config    # deploy FreeSWITCH configs
make sip-up        # start FreeSWITCH (runs sip-config)
make sip-down      # stop FreeSWITCH
make sip-reload    # reload FreeSWITCH XML
```

## FreeSWITCH Config

Files in `freeswitch/`, deployed by `make sip-config`:

| File | Deploys to | Purpose |
|------|-----------|---------|
| `1001.xml` | `directory/default/` | SIP user 1001 (password: 1234) |
| `01_voicebot.xml` | `dialplan/default/` | Extension 6000: auto-answer + record WAV |

ESL: localhost:8021, password ClueCon (FreeSWITCH default).

## Menu Bar App

- **phone.circle** icon when idle
- **mic.fill** when listening
- **text.bubble** when transcribing
- **brain** when asking Claude
- Option+L global hotkey to toggle listen
- Duration picker: 5/8/12/15/20 seconds
- Recent Q&A history (last 5)
