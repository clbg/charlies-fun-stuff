# AgentOperator

macOS menu-bar client for a voice-telephone agent system. AgentOperator is the desktop-side "switchboard operator" (接线员) for a pipeline that bridges a traditional RJ11 telephone — via an HT802 FXS ATA and Asterisk — to Claude Code. The phone becomes a voice terminal; the agent is the operator on the other end of the line.

## Architecture

```
Phone (RJ11) → HT802 (FXS ATA) → Asterisk (PBX)
                                       │ ARI + External Media
                                  AgentOperator
                                       │
                          ┌─────────────┼──────────────┐
                     RTPListener   SpeechRecognizer  ClaudeClient
                    (UDP/μ-law)    (WhisperKit STT)  (claude --bare -p)
```

- **ARIClient** — connects to Asterisk ARI via WebSocket, creates bridge + externalMedia channel on incoming call
- **RTPListener** — receives RTP/UDP, decodes μ-law → PCM16, resamples 8→16 kHz, delivers float32
- **SpeechRecognizer** — accumulates audio, transcribes via WhisperKit (large-v3, on-device)
- **ClaudeClient** — runs `claude --bare -p` subprocess, parses stream-json, returns result
- **CallPipeline** — orchestrates all components: call lifecycle, audio routing, transcription loop (5s), Claude query

## Requirements

- macOS 14+
- Swift 6.1+ (Command Line Tools or Xcode)
- Asterisk (`brew install asterisk`)
- Linphone (SIP softphone, for dev testing)
- `claude` CLI in PATH

## Quick Start (Phase 0 — no SIP)

```bash
make build
swift run AgentOperatorApp --listen            # 8s default
swift run AgentOperatorApp --listen --seconds 12
```

Speak into your Mac mic — WhisperKit transcribes → Claude answers → prints to terminal.

## Quick Start (Phase 1 — with SIP)

> **Note**: Asterisk has no Homebrew formula on macOS. Use FreeSWITCH (`brew install freeswitch`) or Docker Asterisk. See `asterisk/` for config files (need format conversion for FreeSWITCH).

```bash
# 1. Install FreeSWITCH (or Docker Asterisk)
brew install freeswitch
# TODO: convert asterisk/ configs to FreeSWITCH format

# 2. Build and run
make build
swift run AgentOperatorApp

# 3. Configure Linphone or baresip (brew install baresip)
#    SIP account: linphone / linphone123 @ 127.0.0.1:5060
#    Dial 6000 — speak into mic — see Claude response in terminal
```

## SIP Targets

```bash
make sip-config    # copy config files to Asterisk
make sip-up        # start Asterisk (runs sip-config first)
make sip-down      # stop Asterisk
make sip-reload    # reload Asterisk config without restart
```

## Build & Install

```bash
make build         # debug build
make release       # release build
make install       # release + CLI + App bundle + LaunchAgent
make run-app       # run app in debug mode
make test-hello    # sanity-check the CLI
make test          # swift test
make clean         # clean build artifacts
make uninstall     # remove everything
```

## Asterisk Config

All config files are in `asterisk/`:

| File | Purpose |
|------|---------|
| `pjsip.conf` | Linphone endpoint (UDP, ulaw, userpass auth) |
| `extensions.conf` | Extension 6000 → Stasis(voicebot) |
| `ari.conf` | ARI user "voicebot" for WebSocket/REST |
| `http.conf` | HTTP on 127.0.0.1:8088 |
| `modules.conf` | Explicit module loading (autoload=no) |

## Smoke Test

1. Start Asterisk: `make sip-up`
2. Run app: `swift run AgentOperatorApp`
3. Open Linphone, register to 127.0.0.1 as `linphone`/`linphone123`
4. Dial `6000`
5. Say "东京明天天气"
6. Verify Claude response appears in terminal
