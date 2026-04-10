#!/bin/bash
set -euo pipefail

SESSIONS_DIR="$HOME/Library/Application Support/CharlieWidget/sessions"
mkdir -p "$SESSIONS_DIR"

INPUT=$(cat)

read_fields() {
  /usr/bin/python3 -c '
import json, sys

payload = json.load(sys.stdin)

def get(path):
    cur = payload
    for part in path.split("."):
        if isinstance(cur, dict):
            cur = cur.get(part, "")
        else:
            cur = ""
            break
    if cur is None:
        return ""
    return str(cur)

print("\t".join(get(path) for path in sys.argv[1:]))
' "$@" <<<"$INPUT"
}

IFS=$'\t' read -r SESSION_ID CWD EVENT < <(read_fields session_id cwd hook_event_name)

[ -z "$SESSION_ID" ] && exit 0

TARGET_FILE="$SESSIONS_DIR/gemini-$SESSION_ID.json"

case "$EVENT" in
  SessionEnd)
    rm -f "$TARGET_FILE"
    exit 0
    ;;
  SessionStart) STATE="idle" ;;
  BeforeAgent)  STATE="running" ;;
  AfterAgent)   STATE="idle" ;;
  Notification) STATE="pending" ;;
  *)
    exit 0
    ;;
esac

find_gemini_pid() {
  local p=$PPID
  while [ "$p" != "1" ] && [ -n "$p" ]; do
    local cmd
    cmd=$(ps -o command= -p "$p" 2>/dev/null) || break
    if [[ "$cmd" == *"gemini"* ]] || [[ "$cmd" == *"Gemini"* ]]; then
      echo "$p"
      return
    fi
    p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ') || break
  done
  echo "$PPID"
}

GEMINI_PID=$(find_gemini_pid)
TMPFILE=$(mktemp "$SESSIONS_DIR/.tmp.gemini.XXXXXX")

cat > "$TMPFILE" <<ENDJSON
{
  "session_id": "$SESSION_ID",
  "agent": "gemini",
  "cwd": "$CWD",
  "state": "$STATE",
  "pid": $GEMINI_PID,
  "last_updated": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
ENDJSON

mv "$TMPFILE" "$TARGET_FILE"
find "$SESSIONS_DIR" -name "*.json" -mmin +5 -delete 2>/dev/null || true

exit 0
