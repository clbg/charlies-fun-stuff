# Design — CC Monitor

## Architecture

```
Claude Code                          CharlieWidget App
┌──────────────┐                     ┌────────────────────────────────┐
│ Hook events   │                     │                                │
│ (stdin JSON)  │                     │  SessionStore (@Observable)    │
└──────┬───────┘                     │    ↑ FSEvents    ↑ 60s sweep  │
       │                              │    │             │             │
       ▼                              │  ~/…/CharlieWidget/           │
 cc-monitor-hook.sh                   │    sessions/*.json            │
   read stdin                         │                                │
   find ancestor PID                  │  On reload:                    │
   write state file ──────────────→   │    kill(pid, 0) → dead? delete │
                                      │                                │
                                      │  Menu bar: status dots         │
                                      │  Dropdown: tabbed (Sessions |  │
                                      │            Messages)           │
                                      └────────────────────────────────┘

Gemini / Codex (post-MVP)
┌──────────────┐
│ charlie-widget│
│ monitor <cmd> │──── write state file ──→ same directory
└──────────────┘
```

Key: the session state files are the **only interface** between agents and the widget. No socket protocol changes. The widget watches the directory; any process that writes a valid JSON file gets displayed.

## Data Model

```swift
enum AgentKind: String, Codable, Sendable, CaseIterable {
    case claude, gemini, codex, unknown

    var displayName: String { /* "Claude Code", "Gemini CLI", … */ }
    var sfSymbol: String { /* per-agent icon */ }
}

enum SessionState: String, Codable, Sendable {
    case running, idle, pending
}

struct Session: Identifiable, Codable, Sendable {
    let sessionId: String
    let agent: AgentKind
    let cwd: String
    var state: SessionState
    var lastUpdated: Date
    var pid: Int?              // process ID of the agent

    var id: String { sessionId }
    var projectName: String { /* last 2 path components of cwd */ }
    var isProcessDead: Bool { /* kill(pid, 0) != 0 */ }
    var isStale: Bool { /* lastUpdated > 5 min ago */ }
    var shouldRemove: Bool { /* no PID → true; has PID → isProcessDead || isStale */ }
}
```

### State File Schema (on disk)

```json
{
  "session_id": "claude-a3f291",
  "agent": "claude",
  "cwd": "/Users/pencheng/projects/foo",
  "state": "running",
  "pid": 12345,
  "last_updated": "2026-04-10T15:30:00Z"
}
```

Location: `~/Library/Application Support/CharlieWidget/sessions/{session_id}.json`

Uses snake_case on disk (matches Claude Code hook JSON style). Swift model uses `CodingKeys` to bridge to camelCase.

## SessionStore

`@Observable` class, parallel to `MessageStore`.

```swift
@MainActor @Observable
final class SessionStore {
    private(set) var sessions: [Session] = []

    // Computed
    var activeSessions: [Session]  // = sessions (already filtered on reload)
    var runningCount: Int
    var pendingCount: Int
    var idleCount: Int

    // Lifecycle
    func startWatching()           // DispatchSource FSEvents on sessions dir
    func stopWatching()
    func startSweepTimer()         // 60s periodic reload

    // Core
    func reload()                  // scan dir, parse JSON, check PIDs, delete dead
}
```

**Directory watching:** `DispatchSource.makeFileSystemObjectSource` on the sessions directory with `.write` flag. On event → `reload()`. Coalesce rapid events with 300ms debounce.

**PID checking:** On each `reload()`, for every parsed session:
- No `pid` field → legacy format → delete file immediately
- Has `pid` → `kill(pid_t(pid), 0)` — if returns non-zero, process is dead → delete file
- `isStale` (>5 min) → delete file (fallback for edge cases)

**Sweep timer:** 60-second `Task.sleep` loop calls `reload()` to catch dead sessions that don't trigger FSEvents (e.g., CC process killed without writing a final state).

## Menu Bar Changes

### Icon

Append session status dots to the right of the existing unread grid.

```
charlie [■■][■■]  ● ● ○       ← text + unread grid + session dots
                   │ │ └── idle (gray)
                   │ └──── pending (orange)
                   └────── running (blue)
```

Implementation: `MenuBarIcon.make()` accepts `sessions: SessionSummary` and draws colored circles (NSBezierPath ovals).

### Dropdown

Tabbed UI instead of stacked sections:

```
┌──────────────────────────────────┐
│  Sessions (2)  │  Messages (3)   │  ← tab bar with badge counts
├──────────────────────────────────┤
│                                  │
│  ●  charlies-fun-stuff/widget    │
│     running            just now  │
│                                  │
│  ○  projects/foo                 │
│     idle                  3m ago │
│                                  │
├──────────────────────────────────┤
│ 🔇 Mute              Clear All  │
│ 📂 Open Data Folder...          │
└──────────────────────────────────┘
```

- **Sessions tab**: blue badge with active count. Each row: state dot, agent icon, project name, state label, relative time.
- **Messages tab**: red badge with unread count. Existing toast history UI.
- **Clear All**: clears whichever tab is active (session files or messages).
- **Open Data Folder**: opens `~/Library/Application Support/CharlieWidget/` in Finder.

## Component Tree

```
<App>
  MenuBarExtra(icon: MenuBarIcon.make(unread, sessionSummary))
    <HistoryView store={messageStore} sessionStore={sessionStore}>
      TabBar(Sessions | Messages)
      if sessions:
        ForEach(sessionStore.activeSessions)
          <SessionRow session={session} />
      if messages:
        (existing message list)
      Footer:
        Mute | Clear All
        Open Data Folder...
```

## Hook Script

**File:** `scripts/cc-monitor-hook.sh` (in repo), installed to `~/.local/bin/` by `make install`.

```bash
#!/bin/bash
set -euo pipefail

SESSIONS_DIR="$HOME/Library/Application Support/CharlieWidget/sessions"
mkdir -p "$SESSIONS_DIR"

INPUT=$(cat)

parse() { echo "$INPUT" | /usr/bin/python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('$1',''))"; }

EVENT=$(parse hook_event_name)
SESSION_ID=$(parse session_id)
CWD=$(parse cwd)

[ -z "$SESSION_ID" ] && exit 0

case "$EVENT" in
  UserPromptSubmit) STATE="running" ;;
  PreToolUse)       STATE="running" ;;
  Stop)             STATE="idle" ;;
  Notification)     STATE="pending" ;;
  *)                exit 0 ;;
esac

# Walk up process tree to find claude/node ancestor PID
find_cc_pid() {
  local p=$PPID
  while [ "$p" != "1" ] && [ -n "$p" ]; do
    local cmd
    cmd=$(ps -o comm= -p "$p" 2>/dev/null) || break
    if [[ "$cmd" == *"node"* ]] || [[ "$cmd" == *"claude"* ]]; then
      echo "$p"; return
    fi
    p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ') || break
  done
  echo "$PPID"  # fallback
}

CC_PID=$(find_cc_pid)

# Atomic write
TMPFILE=$(mktemp "$SESSIONS_DIR/.tmp.XXXXXX")
cat > "$TMPFILE" <<ENDJSON
{
  "session_id": "$SESSION_ID",
  "agent": "claude",
  "cwd": "$CWD",
  "state": "$STATE",
  "pid": $CC_PID,
  "last_updated": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
ENDJSON
mv "$TMPFILE" "$SESSIONS_DIR/claude-$SESSION_ID.json"

# Cleanup stale files (>5 min fallback)
find "$SESSIONS_DIR" -name "*.json" -mmin +5 -delete 2>/dev/null || true

exit 0
```

## Claude Code Settings

Added to `~/.claude/settings.json` under `hooks`:

```json
{
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
```

All hooks are `async: true` — fire-and-forget, never block the agent.

## Key Decisions

1. **File-based IPC, not socket.** Sessions are updated by external processes (hooks, wrappers) that may not be Swift. Writing a JSON file is universally simple. The widget watches via FSEvents — near-instant reaction without polling.

2. **No new socket commands.** Toast uses socket because it needs request/response (history query). Sessions are write-only from the agent side and read-only from the widget side — files are simpler.

3. **Hook script in bash, not Swift.** Must start fast (<50ms). A bash script calling `/usr/bin/python3` for JSON parsing is fast enough for async hooks.

4. **PID-based cleanup over TTL.** Hook records the ancestor `claude`/`node` process PID. Widget checks `kill(pid, 0)` on each reload — instant detection of dead sessions. 5-minute TTL is only a fallback for edge cases.

5. **Tabbed UI over stacked sections.** Sessions and Messages are separate concerns with different interaction patterns. Tabs keep each panel clean and give full vertical space.

6. **No toast on state transitions.** The Sessions tab itself is the live status panel. Toasting every running→idle transition would be noisy since the user can see the status at a glance.

7. **60-second sweep timer.** Catches dead sessions when no new FSEvents fire (e.g., all CC sessions killed at once). Lightweight — just re-reads the directory and checks PIDs.
