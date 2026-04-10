#!/bin/bash
set -euo pipefail

SESSIONS_DIR="$HOME/Library/Application Support/CharlieWidget/sessions"
mkdir -p "$SESSIONS_DIR"

INPUT=$(cat)

# Parse JSON fields via python3 (available on all macOS)
parse() { echo "$INPUT" | /usr/bin/python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('$1',''))"; }

EVENT=$(parse hook_event_name)
SESSION_ID=$(parse session_id)
CWD=$(parse cwd)

[ -z "$SESSION_ID" ] && exit 0

# Map hook event to session state
case "$EVENT" in
  UserPromptSubmit) STATE="running" ;;
  PreToolUse)       STATE="running" ;;
  Stop)             STATE="idle" ;;
  Notification)     STATE="pending" ;;
  *)                exit 0 ;;
esac

# Find Claude Code (node) ancestor PID by walking up process tree
find_cc_pid() {
  local p=$PPID
  while [ "$p" != "1" ] && [ -n "$p" ]; do
    local cmd
    cmd=$(ps -o comm= -p "$p" 2>/dev/null) || break
    if [[ "$cmd" == *"node"* ]] || [[ "$cmd" == *"claude"* ]]; then
      echo "$p"
      return
    fi
    p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ') || break
  done
  # Fallback: use PPID if ancestor not found
  echo "$PPID"
}

CC_PID=$(find_cc_pid)

# Atomic write: tmp file + rename
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

# Cleanup stale files (>5 min, fallback for sessions without PID check)
find "$SESSIONS_DIR" -name "*.json" -mmin +5 -delete 2>/dev/null || true

exit 0
