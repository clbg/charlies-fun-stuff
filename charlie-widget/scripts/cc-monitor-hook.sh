#!/bin/bash
set -euo pipefail

SESSIONS_DIR="$HOME/Library/Application Support/CharlieWidget/sessions"
mkdir -p "$SESSIONS_DIR"

INPUT=$(cat)

# Debug log with rotation (cap at 1 MB)
DEBUG_LOG="$SESSIONS_DIR/.debug.log"
if [ -f "$DEBUG_LOG" ] && [ "$(stat -f%z "$DEBUG_LOG" 2>/dev/null || echo 0)" -gt 1048576 ]; then
  tail -500 "$DEBUG_LOG" > "$DEBUG_LOG.tmp" && mv "$DEBUG_LOG.tmp" "$DEBUG_LOG"
fi
echo "$(date -u +%H:%M:%S) $INPUT" >> "$DEBUG_LOG"

# Parse all fields in a single python3 invocation (tab-separated)
IFS=$'\t' read -r EVENT SESSION_ID CWD TOOL_NAME PERM_MODE < <(
  /usr/bin/python3 -c "
import sys, json
d = json.loads(sys.stdin.read())
print(d.get('hook_event_name',''), d.get('session_id',''), d.get('cwd',''),
      d.get('tool_name',''), d.get('permission_mode',''), sep='\t')
" <<< "$INPUT" 2>/dev/null
) || exit 0

[ -z "$SESSION_ID" ] && exit 0

# Map hook event to session state
case "$EVENT" in
  UserPromptSubmit) STATE="running" ;;
  PreToolUse)       STATE="running" ;;
  PostToolUse)      STATE="running" ;;
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
