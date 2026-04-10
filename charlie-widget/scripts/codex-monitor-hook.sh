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

case "$EVENT" in
  SessionStart)      STATE="idle" ;;
  UserPromptSubmit)  STATE="running" ;;
  PreToolUse)        STATE="running" ;;
  PostToolUse)       STATE="running" ;;
  Stop)              STATE="idle" ;;
  *)
    exit 0
    ;;
esac

find_codex_pid() {
  local p=$PPID
  while [ "$p" != "1" ] && [ -n "$p" ]; do
    local cmd
    cmd=$(ps -o command= -p "$p" 2>/dev/null) || break
    if [[ "$cmd" == *"codex"* ]] || [[ "$cmd" == *"Codex"* ]]; then
      echo "$p"
      return
    fi
    p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ') || break
  done
  echo "$PPID"
}

CODEX_PID=$(find_codex_pid)
TARGET_FILE="$SESSIONS_DIR/codex-$SESSION_ID.json"
TMPFILE=$(mktemp "$SESSIONS_DIR/.tmp.codex.XXXXXX")

cat > "$TMPFILE" <<ENDJSON
{
  "session_id": "$SESSION_ID",
  "agent": "codex",
  "cwd": "$CWD",
  "state": "$STATE",
  "pid": $CODEX_PID,
  "last_updated": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
ENDJSON

mv "$TMPFILE" "$TARGET_FILE"
find "$SESSIONS_DIR" -name "*.json" -mmin +5 -delete 2>/dev/null || true

if [ "$EVENT" = "Stop" ]; then
  printf '{}\n'
fi

exit 0
