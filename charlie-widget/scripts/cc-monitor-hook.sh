#!/bin/bash
set -euo pipefail

SESSIONS_DIR="$HOME/Library/Application Support/CharlieWidget/sessions"
mkdir -p "$SESSIONS_DIR"

INPUT=$(cat)

# Debug: log raw payloads to diagnose Notification timing
echo "$(date -u +%H:%M:%S) $INPUT" >> "$SESSIONS_DIR/.debug.log"

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
# For PreToolUse: predict whether tool needs approval based on permission_mode
case "$EVENT" in
  UserPromptSubmit) STATE="running" ;;
  PreToolUse)
    STATE="running"
    # In acceptEdits mode, Bash/Agent need approval
    if [[ "$PERM_MODE" == "acceptEdits" ]]; then
      case "$TOOL_NAME" in Bash|Agent) STATE="pending" ;; esac
    # In default mode, most tools except read-only need approval
    elif [[ "$PERM_MODE" == "default" ]]; then
      case "$TOOL_NAME" in Read|Glob|Grep) ;; *) STATE="pending" ;; esac
    fi
    ;;
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
