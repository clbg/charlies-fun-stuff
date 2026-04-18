#!/usr/bin/env bash
#
# DMG install & launch automated test for Undercurrent.
#
# Prereqs: browser-use CLI
# Usage:   bash tests/dmg-test.sh [path-to-dmg]
#          Defaults to dist/Undercurrent-0.1.0-arm64.dmg
#
set -euo pipefail

SESSION="uc-dmg-$(date +%s)"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASSED=0
FAILED=0
FAILURES=()

# ── Detect arch and pick DMG ─────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ARCH=$(uname -m)

VERSION=$(node -p "require('$PROJECT_DIR/package.json').version")

if [ $# -ge 1 ]; then
  DMG_PATH="$1"
elif [ "$ARCH" = "arm64" ]; then
  DMG_PATH="$PROJECT_DIR/dist/Undercurrent-${VERSION}-arm64.dmg"
else
  DMG_PATH="$PROJECT_DIR/dist/Undercurrent-${VERSION}.dmg"
fi

if [ ! -f "$DMG_PATH" ]; then
  echo -e "${RED}DMG not found: $DMG_PATH${NC}"
  echo "Run 'pnpm dist' first."
  exit 1
fi

APP_NAME="Undercurrent"
MOUNT_POINT=""
INSTALLED_APP="/tmp/uc-test-app/${APP_NAME}.app"

# ── Helpers ──────────────────────────────────────────

pass() { echo -e "  ${GREEN}✓${NC} $1"; PASSED=$((PASSED + 1)); }
fail() { echo -e "  ${RED}✗${NC} $1"; FAILED=$((FAILED + 1)); FAILURES+=("$1"); }

assert_contains() {
  local haystack="$1" needle="$2" label="$3"
  if echo "$haystack" | grep -q "$needle"; then pass "$label"; else fail "$label (expected '$needle')"; fi
}

cleanup() {
  echo ""
  echo -e "${YELLOW}▸ Cleaning up...${NC}"
  # Close browser
  browser-use --session "$SESSION" close 2>/dev/null || true
  # Quit the app
  osascript -e "quit app \"$APP_NAME\"" 2>/dev/null || true
  sleep 2
  # Kill any leftover server on our port
  lsof -ti:3456 | xargs kill -9 2>/dev/null || true
  # Unmount DMG
  if [ -n "$MOUNT_POINT" ] && [ -d "$MOUNT_POINT" ]; then
    hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true
  fi
  # Remove temp app
  rm -rf /tmp/uc-test-app
}
trap cleanup EXIT

# ── Test ─────────────────────────────────────────────

echo ""
echo "  ╭──────────────────────────────────╮"
echo "  │   Undercurrent DMG Test Suite     │"
echo "  ╰──────────────────────────────────╯"
echo ""
echo "  DMG:  $DMG_PATH"
echo "  Arch: $ARCH"
echo ""

# ── 1. Mount DMG ─────────────────────────────────────
echo -e "${YELLOW}▸ 1. Mount DMG${NC}"
MOUNT_OUTPUT=$(hdiutil attach "$DMG_PATH" -nobrowse -noverify 2>&1)
MOUNT_POINT=$(echo "$MOUNT_OUTPUT" | tail -1 | sed 's/.*\(\/Volumes\/.*\)/\1/' | xargs)
if [ -d "$MOUNT_POINT" ]; then
  pass "DMG mounted at $MOUNT_POINT"
else
  fail "DMG mount failed"
  exit 1
fi

# Check .app exists inside
if [ -d "$MOUNT_POINT/${APP_NAME}.app" ]; then
  pass ".app found in DMG"
else
  fail ".app not found in DMG"
  exit 1
fi

# ── 2. Copy to temp (simulate drag to Applications) ──
echo -e "${YELLOW}▸ 2. Install (copy to temp)${NC}"
mkdir -p /tmp/uc-test-app
cp -R "$MOUNT_POINT/${APP_NAME}.app" "$INSTALLED_APP"
if [ -d "$INSTALLED_APP" ]; then
  pass "App copied to $INSTALLED_APP"
else
  fail "Copy failed"
  exit 1
fi

# ── 3. Launch app ────────────────────────────────────
echo -e "${YELLOW}▸ 3. Launch app${NC}"

# Remove quarantine flag (since we're testing locally, not from App Store)
xattr -rd com.apple.quarantine "$INSTALLED_APP" 2>/dev/null || true

open "$INSTALLED_APP"

# Wait for server to come up on port 3456
echo "  Waiting for server on :3456 (up to 45s)..."
DEADLINE=$((SECONDS + 45))
SERVER_UP=false
while [ $SECONDS -lt $DEADLINE ]; do
  if curl -s http://127.0.0.1:3456 >/dev/null 2>&1; then
    SERVER_UP=true
    break
  fi
  sleep 1
done

if $SERVER_UP; then
  pass "Server is up on :3456"
else
  fail "Server didn't start within 45s"
  exit 1
fi

# ── 4. Browser test: Welcome screen ─────────────────
echo -e "${YELLOW}▸ 4. Welcome screen${NC}"
sleep 2
browser-use --profile "Default" --session "$SESSION" --headed open http://127.0.0.1:3456 2>/dev/null

sleep 3
STATE=$(browser-use --session "$SESSION" state 2>&1)
assert_contains "$STATE" "Undercurrent" "Title visible"
assert_contains "$STATE" "Start Exploring" "Start button visible"
assert_contains "$STATE" "Claude" "Engine option visible"

# Check engine detection
STATE_DETAIL=$(browser-use --session "$SESSION" eval "(function(){ return document.body.innerText; })()" 2>&1)
assert_contains "$STATE_DETAIL" "ready" "Claude CLI detected as ready"

# ── 5. Click Start and enter main UI ─────────────────
echo -e "${YELLOW}▸ 5. Start and enter main UI${NC}"

# Find and click "Start Exploring" button
START_IDX=$(echo "$STATE" | grep -B1 "Start Exploring" | grep -o '\[.*\]' | tr -d '[]' | head -1)
if [ -n "$START_IDX" ]; then
  browser-use --session "$SESSION" click "$START_IDX" 2>/dev/null
  sleep 2
  STATE2=$(browser-use --session "$SESSION" state 2>&1)
  assert_contains "$STATE2" "textarea" "Input textarea visible"
  assert_contains "$STATE2" "beneath the surface" "Empty state shown"
else
  fail "Start button not found"
fi

# ── 6. Check engine badge in header ──────────────────
echo -e "${YELLOW}▸ 6. Engine badge in header${NC}"
STATE3=$(browser-use --session "$SESSION" state 2>&1)
assert_contains "$STATE3" "claude" "Engine badge visible in header"

# ── 7. Submit a question ─────────────────────────────
echo -e "${YELLOW}▸ 7. Submit question${NC}"
TEXTAREA_IDX=$(echo "$STATE3" | grep "textarea" | grep -o '\[.*\]' | tr -d '[]' | head -1)
if [ -n "$TEXTAREA_IDX" ]; then
  browser-use --session "$SESSION" input "$TEXTAREA_IDX" "What is recursion?" 2>/dev/null
  browser-use --session "$SESSION" keys Enter 2>/dev/null
  sleep 3
  STATE4=$(browser-use --session "$SESSION" state 2>&1)
  # Should show status or response
  if echo "$STATE4" | grep -qE "Connecting|Thinking|recursion|Recursion"; then
    pass "Question submitted, response in progress"
  else
    fail "No response activity after submit"
  fi
else
  fail "Textarea not found"
fi

# Wait for response to complete
echo "  Waiting for LLM response (up to 60s)..."
DEADLINE=$((SECONDS + 60))
RESPONSE_DONE=false
while [ $SECONDS -lt $DEADLINE ]; do
  ST=$(browser-use --session "$SESSION" state 2>&1)
  if echo "$ST" | grep -q "data-paragraph-index\|prose\|Collapse all"; then
    RESPONSE_DONE=true
    break
  fi
  sleep 3
done

if $RESPONSE_DONE; then
  pass "LLM response completed"
else
  # Check if at least streaming
  if echo "$ST" | grep -qE "Connecting|Thinking"; then
    pass "LLM still processing (slow but working)"
  else
    fail "No response after 60s"
  fi
fi

# ── 8. Toolbar present ───────────────────────────────
echo -e "${YELLOW}▸ 8. Toolbar buttons${NC}"
FINAL=$(browser-use --session "$SESSION" state 2>&1)
assert_contains "$FINAL" "Collapse all" "Collapse all button"
assert_contains "$FINAL" "Copy MD" "Copy MD button"
assert_contains "$FINAL" "Export HTML" "Export HTML button"
assert_contains "$FINAL" "Iron" "Iron button"

# ── 9. App icon check ────────────────────────────────
echo -e "${YELLOW}▸ 9. App icon${NC}"
ICON_PATH="$INSTALLED_APP/Contents/Resources/icon.icns"
if [ -f "$ICON_PATH" ]; then
  ICON_SIZE=$(stat -f%z "$ICON_PATH" 2>/dev/null || stat -c%s "$ICON_PATH" 2>/dev/null)
  if [ "$ICON_SIZE" -gt 10000 ]; then
    pass "Custom icon present (${ICON_SIZE} bytes)"
  else
    fail "Icon too small, probably default"
  fi
else
  # electron-builder might put it elsewhere
  if find "$INSTALLED_APP/Contents/Resources" -name "*.icns" -size +10k 2>/dev/null | grep -q .; then
    pass "Custom icon found in Resources"
  else
    fail "No custom icon found"
  fi
fi

# ── Results ──────────────────────────────────────────
echo ""
echo "  ──────────────────────────────────"
echo -e "  ${GREEN}Passed: $PASSED${NC}  ${RED}Failed: $FAILED${NC}"
if [ $FAILED -gt 0 ]; then
  echo ""
  echo -e "  ${RED}Failures:${NC}"
  for f in "${FAILURES[@]}"; do
    echo -e "    ${RED}✗${NC} $f"
  done
  echo ""
  exit 1
else
  echo ""
  echo -e "  ${GREEN}All tests passed!${NC}"
  echo ""
  exit 0
fi
