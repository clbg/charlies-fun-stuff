# User Stories — CC Monitor

## Vision

A menu bar feature that gives at-a-glance visibility into all running AI coding agent sessions (Claude Code, Gemini CLI, Codex CLI, etc.). Each session shows a live status indicator — spinning for active, dot for idle, alert for pending approval — so I never miss a completed task or an approval prompt buried in another terminal tab.

**Scope:** Feature 2 of Charlie Widget. Builds on existing menu bar app + IPC infrastructure.

---

## Core Stories (MVP)

### US-1: See All Sessions at a Glance

**As a** user with multiple AI agent terminals open,
**I want to** see a compact status summary in the menu bar,
**so that** I know what's happening without switching to each terminal.

**Acceptance Criteria:**
- Menu bar icon area shows colored dots/symbols for each active session
- States: `running` (animated/spinner), `idle` (dim dot), `pending` (alert dot)
- Dead sessions are auto-cleaned by PID detection (`kill(pid, 0)`), with 5-minute TTL fallback
- Zero sessions → no extra indicators (just the existing Charlie Widget icon)

### US-2: Inspect Session Details

**As a** user,
**I want to** click the menu bar to see details about each session,
**so that** I can tell which project each session belongs to.

**Acceptance Criteria:**
- Dropdown uses a tabbed UI: **Sessions** tab and **Messages** tab
- Each entry shows: status icon, project directory (last 2 path components), time since last update
- Click an entry → no action for MVP (future: focus that terminal)
- Empty state: "No active sessions"

### ~~US-3: Get Notified on State Changes~~ (removed)

Removed in favor of the tabbed UI — Sessions tab itself serves as the live status panel, making toast notifications for state changes redundant noise.

### US-4: Claude Code Integration via Hooks

**As a** Claude Code user,
**I want to** have session status reported automatically via hooks,
**so that** I don't need to change my workflow.

**Acceptance Criteria:**
- A hook script reads Claude Code's JSON input from stdin, extracts `session_id` and `cwd`
- Hooks configured in `~/.claude/settings.json` for events: `UserPromptSubmit`, `PreToolUse`, `Stop`, `Notification`
- State mapping:
  - `UserPromptSubmit` → `running`
  - `PreToolUse` → `running` (covers resume after pending)
  - `Stop` → `idle`
  - `Notification(permission_prompt)` → `pending`
- Hook script writes to CharlieWidget's data directory, not `~/.claude/`
- Hook is `async: true` so it never blocks Claude Code

---

## Enhancement Stories (Post-MVP)

### US-5: Generic Agent Wrapper

**As a** user of Gemini CLI, Codex CLI, or other agents without hooks,
**I want to** wrap any CLI agent to get the same status monitoring,
**so that** all my agent sessions appear in one place.

**Acceptance Criteria:**
- CLI command: `charlie-widget monitor <command>` (e.g., `charlie-widget monitor gemini`)
- Wrapper launches the child process, relays stdin/stdout transparently
- Detects state by output activity:
  - Child producing output → `running`
  - No output for N seconds → `idle`
  - Child exits → remove session
- Limitation: cannot distinguish `pending` from `idle` (no hook system)

### US-6: Click to Focus Terminal

**As a** user,
**I want to** click a session entry to switch to that terminal,
**so that** I can quickly act on a pending approval.

### US-7: Process-Based Auto-Discovery

**As a** user,
**I want to** have agent sessions discovered automatically by scanning running processes,
**so that** I get monitoring even without hooks or wrappers.

### US-8: Open Data Directory from Menu

**As a** user,
**I want to** have a menu item that opens the CharlieWidget data directory in Finder,
**so that** I can quickly inspect session files and debug without remembering the path.

**Acceptance Criteria:**
- Menu dropdown includes "Open Data Folder..." at the bottom
- Opens `~/Library/Application Support/CharlieWidget/` in Finder
- This is a general widget feature, not specific to CC Monitor

### US-9: Session History

**As a** user,
**I want to** see recently completed sessions (last hour),
**so that** I can review what finished while I was away.

---

### US-10: Bubble Overlay for Session State Awareness

**As a** user with multiple AI agent sessions,
**I want to** see floating animated bubbles on my screen reflecting session states,
**so that** I have ambient, at-a-glance awareness of pending approvals and completed tasks without checking the menu bar.

**Acceptance Criteria:**
- Full-screen transparent overlay with floating bubbles
- Each pending session → one warm-toned bubble (amber/coral gradient)
- Each idle session → one cool-toned bubble (cyan/blue gradient)
- Running sessions → no bubble
- Bubbles show agent letter (C/G/X/K) inside
- Bubbles drift randomly, bounce off screen edges
- Bubbles persist until session state changes (no auto-fade)
- Click a bubble to dismiss it; dismissed bubbles don't reappear until session state changes
- Overlay is click-through except on bubbles, appears on all spaces
- Off by default, toggled via CLI: `charlie-widget bubble on/off/status`
- Max 12 bubbles on screen

---

## Technical Stories (Internal)

### TS-1: State File Protocol

A shared contract between all adapters (hooks, wrapper, process monitor) and the widget.

- **Location:** `~/Library/Application Support/CharlieWidget/sessions/{session_id}.json`
- **Schema:**
  ```json
  {
    "session_id": "string",
    "agent": "claude | gemini | codex | unknown",
    "cwd": "/absolute/path/to/project",
    "state": "running | idle | pending",
    "pid": 12345,
    "last_updated": "ISO-8601 timestamp"
  }
  ```
- Session ID format: `{agent}-{unique}` (e.g., `claude-a3f291`, `gemini-wrapper-7b2c`)
- Files are the IPC mechanism — no socket protocol changes needed for MVP
- Widget watches the directory via FSEvents for real-time updates

### TS-2: Session Cleanup

- **Primary**: PID-based — widget checks `kill(pid, 0)` on each reload; dead PID → delete file
- **Fallback**: 5-minute TTL for sessions without PID field (legacy or non-hook sources)
- **Sweep timer**: 60-second periodic reload catches dead sessions between FSEvents
- Hook script also cleans files older than 5 min on each invocation as a side effect
- Sessions without PID field are treated as legacy and immediately cleaned up

### TS-3: Hook Script

- Single bash script (`cc-monitor-hook.sh`) handling all Claude Code hook events
- Reads JSON from stdin, switches on `hook_event_name` to determine state
- Finds Claude Code PID by walking ancestor process tree (`$PPID` → node/claude)
- Writes/updates the session's state file atomically (write to tmp + rename)
- Installed to `~/.local/bin/cc-monitor-hook.sh` by `make install`

### TS-4: CLI Extension

- `charlie-widget sessions` — list active sessions (JSON)
- `charlie-widget sessions --clear` — remove all session files
- Communicates via state files, not socket (read-only for this subcommand)

---

## Technical Constraints

- **Data directory:** `~/Library/Application Support/CharlieWidget/sessions/`
- **IPC for state:** File-based (FSEvents), not socket — keeps it decoupled from widget process
- **Hook scripts must be async** — never block the AI agent
- **Atomic writes** — prevent widget from reading partial JSON
- **No agent source modifications** — only use each agent's extension points or external wrapping
