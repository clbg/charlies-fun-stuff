#!/usr/bin/env bash
#
# Undercurrent — comprehensive browser tests using browser-use CLI.
#
# Prereqs:
#   - Next.js dev server running at localhost:3000
#   - browser-use CLI installed and on PATH
#
# Usage:
#   ./tests/browser-test.sh
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
BASE_URL="http://localhost:3000"
SESSION="uc-test-$(date +%s)"
PROFILE="Default"
LLM_TIMEOUT=30          # seconds to wait for LLM responses
POLL_INTERVAL=2          # seconds between status polls

PASSED=0
FAILED=0
ERRORS=()

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
GREEN=$'\033[0;32m'
RED=$'\033[0;31m'
YELLOW=$'\033[0;33m'
CYAN=$'\033[0;36m'
RESET=$'\033[0m'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()      { echo "${CYAN}[TEST]${RESET} $*"; }
log_pass() { echo "${GREEN}  PASS${RESET} $*"; PASSED=$((PASSED + 1)); }
log_fail() { echo "${RED}  FAIL${RESET} $*"; FAILED=$((FAILED + 1)); ERRORS+=("$*"); }
log_step() { echo ""; echo "${YELLOW}--- $* ---${RESET}"; }

# Cleanup: always close the browser session on exit
cleanup() {
  log "Cleaning up session ${SESSION}..."
  browser-use --session "$SESSION" close 2>/dev/null || true
}
trap cleanup EXIT

# Run a browser-use command and capture stdout. Exits on hard failure only
# when the command itself is broken (not when we're just checking output).
bu() {
  browser-use --session "$SESSION" "$@" 2>&1
}

# Open the browser (first call needs --profile and --headed)
bu_open() {
  browser-use --profile "$PROFILE" --session "$SESSION" --headed open "$1" 2>&1
}

# Get page state as text
get_state() {
  bu state
}

# Take a screenshot (useful for debugging, output goes to stdout)
take_screenshot() {
  bu screenshot
}

# Evaluate JS in the browser and return the result
js_eval() {
  bu eval "$1"
}

# Assert that a string is present in the given text.
# Usage: assert_contains "$haystack" "needle" "description"
assert_contains() {
  local haystack="$1" needle="$2" desc="$3"
  if echo "$haystack" | grep -qi "$needle"; then
    log_pass "$desc"
  else
    log_fail "$desc (expected to find '${needle}')"
  fi
}

# Assert that a string is NOT present in the given text.
assert_not_contains() {
  local haystack="$1" needle="$2" desc="$3"
  if echo "$haystack" | grep -qi "$needle"; then
    log_fail "$desc (unexpectedly found '${needle}')"
  else
    log_pass "$desc"
  fi
}

# Wait until get_state() output contains a specific string, or time out.
# Usage: wait_for_text "some text" <timeout_seconds> "description"
# Returns 0 on success, 1 on timeout.
wait_for_text() {
  local needle="$1" timeout="${2:-$LLM_TIMEOUT}" desc="${3:-waiting for '$1'}"
  local elapsed=0
  log "Waiting up to ${timeout}s for: ${needle} (${desc})"
  while [ "$elapsed" -lt "$timeout" ]; do
    local state
    state=$(get_state 2>/dev/null) || true
    if echo "$state" | grep -qi "$needle"; then
      return 0
    fi
    sleep "$POLL_INTERVAL"
    elapsed=$((elapsed + POLL_INTERVAL))
  done
  return 1
}

# Wait until JS expression evaluates to a truthy string, or time out.
# Usage: wait_for_js "document.querySelector('p')" <timeout> "desc"
wait_for_js() {
  local expr="$1" timeout="${2:-$LLM_TIMEOUT}" desc="${3:-waiting for JS}"
  local elapsed=0
  log "Waiting up to ${timeout}s for JS: ${desc}"
  while [ "$elapsed" -lt "$timeout" ]; do
    local result
    result=$(js_eval "$expr" 2>/dev/null) || true
    # browser-use eval returns the JS result; check it's non-empty and not "null"/"undefined"/"false"
    if [ -n "$result" ] && [ "$result" != "null" ] && [ "$result" != "undefined" ] && [ "$result" != "false" ]; then
      return 0
    fi
    sleep "$POLL_INTERVAL"
    elapsed=$((elapsed + POLL_INTERVAL))
  done
  return 1
}

# Select text inside the first matching element via JS.
# This creates a DOM Selection that the app's useSelection hook will detect.
select_text_in() {
  local selector="$1"
  js_eval "
    (function() {
      var el = document.querySelector('${selector}');
      if (!el) return 'element-not-found';
      var range = document.createRange();
      range.selectNodeContents(el);
      var sel = window.getSelection();
      sel.removeAllRanges();
      sel.addRange(range);
      // Dispatch mouseup so the app detects the selection
      el.dispatchEvent(new MouseEvent('mouseup', { bubbles: true }));
      return 'selected';
    })()
  "
}

# ---------------------------------------------------------------------------
# Pre-flight check
# ---------------------------------------------------------------------------
log "Pre-flight: verifying dev server at ${BASE_URL}"
if ! curl -s --max-time 5 "$BASE_URL" > /dev/null 2>&1; then
  echo "${RED}ERROR: Dev server not reachable at ${BASE_URL}. Start it first (pnpm dev).${RESET}"
  exit 1
fi
log "Dev server is up."

# ===========================================================================
# TEST 1: Page Load
# ===========================================================================
log_step "Test 1: Page Load"

bu_open "$BASE_URL" > /dev/null
sleep 2  # let page hydrate

STATE=$(get_state)

assert_contains "$STATE" "Undercurrent" "Page title 'Undercurrent' is visible"
assert_contains "$STATE" "textarea" "Input textarea exists"
assert_contains "$STATE" "Explore" "Explore button is present"
assert_contains "$STATE" "beneath the surface" "Empty state text is shown"

# ===========================================================================
# TEST 2: Submit a Question
# ===========================================================================
log_step "Test 2: Submit Question"

# Find the textarea index and type into it
TEXTAREA_INDEX=$(js_eval "
  (function() {
    var ta = document.querySelector('textarea');
    if (!ta) return '';
    ta.focus();
    return 'focused';
  })()
")

if [ "$TEXTAREA_INDEX" = "focused" ]; then
  log_pass "Textarea found and focused"
else
  log_fail "Could not find textarea"
fi

# Type the question using eval to set React state via native input events
js_eval "
  (function() {
    var ta = document.querySelector('textarea');
    if (!ta) return;
    var nativeInputValueSetter = Object.getOwnPropertyDescriptor(
      window.HTMLTextAreaElement.prototype, 'value'
    ).set;
    nativeInputValueSetter.call(ta, 'What is quantum entanglement?');
    ta.dispatchEvent(new Event('input', { bubbles: true }));
    ta.dispatchEvent(new Event('change', { bubbles: true }));
  })()
"
sleep 1

# Verify the text was entered
STATE=$(get_state)
assert_contains "$STATE" "quantum entanglement" "Question text entered in textarea"

# Click the Explore button by submitting the form via JS (most reliable)
js_eval "
  (function() {
    var btn = document.querySelector('button[type=\"submit\"]');
    if (btn) btn.click();
  })()
"
sleep 2

STATE=$(get_state)
assert_contains "$STATE" "Connecting to Claude CLI" "Status shows 'Connecting to Claude CLI...'"
assert_contains "$STATE" "quantum entanglement" "Original question is echoed below input"

# ===========================================================================
# TEST 3: Response Rendering
# ===========================================================================
log_step "Test 3: Response Rendering"

if wait_for_js "document.querySelectorAll('[data-node-id] .prose p').length > 0" "$LLM_TIMEOUT" "response paragraphs"; then
  log_pass "Response paragraphs rendered within timeout"
else
  log_fail "No response paragraphs appeared within ${LLM_TIMEOUT}s"
fi

# Wait for streaming to finish (status becomes 'done')
if wait_for_js "
  (function() {
    var nodes = document.querySelectorAll('[data-node-id]');
    if (nodes.length === 0) return false;
    var first = nodes[0];
    // Check that the spinner is gone (status indicator disappears when done)
    return first.querySelector('.animate-spin') === null &&
           first.querySelectorAll('.prose p').length > 0;
  })()
" 60 "streaming complete"; then
  log_pass "Response streaming completed"
else
  log_fail "Response did not finish streaming within 60s"
fi

# Verify prose content
PARAGRAPH_COUNT=$(js_eval "document.querySelectorAll('[data-node-id] .prose p').length")
log "Found ${PARAGRAPH_COUNT} paragraph(s) in response"
if [ -n "$PARAGRAPH_COUNT" ] && [ "$PARAGRAPH_COUNT" -gt 0 ] 2>/dev/null; then
  log_pass "Response contains ${PARAGRAPH_COUNT} paragraph(s)"
else
  log_fail "No paragraphs found in response"
fi

# ===========================================================================
# TEST 4: Select Text & Go Deeper
# ===========================================================================
log_step "Test 4: Select Text & Go Deeper"

# Select text in the first paragraph of the response
SELECT_RESULT=$(select_text_in "[data-paragraph-index='0'] p")
if [ "$SELECT_RESULT" = "selected" ]; then
  log_pass "Text selected in first paragraph"
else
  log_fail "Could not select text (got: ${SELECT_RESULT})"
fi

sleep 1

# Check that the floating SelectionToolbar appeared
if wait_for_js "document.querySelector('[data-selection-toolbar]') !== null" 5 "selection toolbar"; then
  log_pass "Selection toolbar appeared"
else
  log_fail "Selection toolbar did not appear"
fi

STATE=$(get_state)
assert_contains "$STATE" "Go deeper" "Toolbar has 'Go deeper' button"
assert_contains "$STATE" "Ask about this" "Toolbar has 'Ask about this' button"

# Click "Go deeper"
js_eval "
  (function() {
    var toolbar = document.querySelector('[data-selection-toolbar]');
    if (!toolbar) return 'no-toolbar';
    var buttons = toolbar.querySelectorAll('button');
    for (var i = 0; i < buttons.length; i++) {
      if (buttons[i].textContent.trim() === 'Go deeper') {
        buttons[i].click();
        return 'clicked';
      }
    }
    return 'button-not-found';
  })()
"
sleep 2

# Verify a child node spawned (CollapsibleBlock appears with border-l-2)
STATE=$(get_state)
assert_contains "$STATE" "Connecting to Claude CLI" "Drill-down spawned (status indicator visible)"

# ===========================================================================
# TEST 5: Drill-Down Response
# ===========================================================================
log_step "Test 5: Drill-Down Response"

# Wait for the nested response to render
if wait_for_js "
  (function() {
    var collapsibles = document.querySelectorAll('.border-l-2');
    if (collapsibles.length === 0) return false;
    var nested = collapsibles[0].querySelectorAll('.prose p');
    return nested.length > 0;
  })()
" "$LLM_TIMEOUT" "nested response paragraphs"; then
  log_pass "Drill-down response rendered"
else
  log_fail "Drill-down response did not render within ${LLM_TIMEOUT}s"
fi

# Wait for drill-down streaming to finish
if wait_for_js "
  (function() {
    var collapsibles = document.querySelectorAll('.border-l-2');
    if (collapsibles.length === 0) return false;
    // No spinners inside the collapsible = done
    return collapsibles[0].querySelectorAll('.animate-spin').length === 0 &&
           collapsibles[0].querySelectorAll('.prose p').length > 0;
  })()
" 60 "drill-down streaming complete"; then
  log_pass "Drill-down streaming completed"
else
  log_fail "Drill-down did not finish streaming within 60s"
fi

# Verify indentation (ml-4 class = left margin on the nested block)
NESTED_EXISTS=$(js_eval "document.querySelector('.ml-4.border-l-2') !== null")
if [ "$NESTED_EXISTS" = "true" ]; then
  log_pass "Nested content has indentation (ml-4 border-l-2)"
else
  log_fail "Nested content indentation not found"
fi

# ===========================================================================
# TEST 6: Select & Ask About This
# ===========================================================================
log_step "Test 6: Select Text & Ask About This"

# Select text in a paragraph of the root response (not the nested one)
SELECT_RESULT=$(select_text_in "[data-node-id]:first-child > div:first-of-type [data-paragraph-index='0'] p")
if [ "$SELECT_RESULT" != "selected" ]; then
  # Fallback: try any paragraph
  SELECT_RESULT=$(select_text_in "[data-paragraph-index='0'] p")
fi
sleep 1

# Wait for toolbar
if wait_for_js "document.querySelector('[data-selection-toolbar]') !== null" 5 "selection toolbar for ask"; then
  log_pass "Selection toolbar appeared for Ask About"
else
  log_fail "Selection toolbar did not appear for Ask About"
fi

# Click "Ask about this"
js_eval "
  (function() {
    var toolbar = document.querySelector('[data-selection-toolbar]');
    if (!toolbar) return 'no-toolbar';
    var buttons = toolbar.querySelectorAll('button');
    for (var i = 0; i < buttons.length; i++) {
      if (buttons[i].textContent.trim() === 'Ask about this') {
        buttons[i].click();
        return 'clicked';
      }
    }
    return 'button-not-found';
  })()
"
sleep 1

# Verify the input field appeared in the toolbar
ASK_INPUT_EXISTS=$(js_eval "document.querySelector('[data-selection-toolbar] input') !== null")
if [ "$ASK_INPUT_EXISTS" = "true" ]; then
  log_pass "Ask input field appeared in toolbar"
else
  log_fail "Ask input field did not appear"
fi

# Type a question into the ask input
js_eval "
  (function() {
    var input = document.querySelector('[data-selection-toolbar] input');
    if (!input) return;
    var nativeSet = Object.getOwnPropertyDescriptor(
      window.HTMLInputElement.prototype, 'value'
    ).set;
    nativeSet.call(input, 'Why is this important for computing?');
    input.dispatchEvent(new Event('input', { bubbles: true }));
    input.dispatchEvent(new Event('change', { bubbles: true }));
  })()
"
sleep 1

# Submit the question by clicking the Ask button
js_eval "
  (function() {
    var toolbar = document.querySelector('[data-selection-toolbar]');
    if (!toolbar) return;
    var btn = toolbar.querySelector('button[type=\"submit\"]');
    if (btn) btn.click();
  })()
"
sleep 2

# Verify another child spawned
CHILD_COUNT=$(js_eval "document.querySelectorAll('.border-l-2').length")
log "Collapsible child blocks: ${CHILD_COUNT}"
if [ -n "$CHILD_COUNT" ] && [ "$CHILD_COUNT" -ge 2 ] 2>/dev/null; then
  log_pass "Ask About spawned a second child node (${CHILD_COUNT} total)"
else
  log_fail "Expected at least 2 collapsible blocks, got ${CHILD_COUNT}"
fi

# Wait for the ask-about response
if wait_for_js "
  (function() {
    var blocks = document.querySelectorAll('.border-l-2');
    if (blocks.length < 2) return false;
    var last = blocks[blocks.length - 1];
    return last.querySelectorAll('.prose p').length > 0 &&
           last.querySelectorAll('.animate-spin').length === 0;
  })()
" 60 "ask-about response complete"; then
  log_pass "Ask About response rendered and completed"
else
  log_fail "Ask About response did not complete within 60s"
fi

# ===========================================================================
# TEST 7: Collapse / Expand
# ===========================================================================
log_step "Test 7: Collapse / Expand"

# Find the first collapse toggle button (the one with the triangle character)
TOGGLE_RESULT=$(js_eval "
  (function() {
    var toggles = document.querySelectorAll('.border-l-2 > button');
    if (toggles.length === 0) return 'no-toggle';
    toggles[0].click();
    return 'clicked';
  })()
")

if [ "$TOGGLE_RESULT" = "clicked" ]; then
  log_pass "Collapse toggle clicked"
else
  log_fail "Could not find collapse toggle"
fi

sleep 0.5

# Check that content is hidden (the child div with mt-1 should not exist for collapsed)
CONTENT_HIDDEN=$(js_eval "
  (function() {
    var blocks = document.querySelectorAll('.border-l-2');
    if (blocks.length === 0) return 'no-blocks';
    var first = blocks[0];
    var content = first.querySelector('.mt-1');
    return content === null ? 'hidden' : 'visible';
  })()
")

if [ "$CONTENT_HIDDEN" = "hidden" ]; then
  log_pass "Content is hidden after collapse"
else
  log_fail "Content is still visible after collapse (got: ${CONTENT_HIDDEN})"
fi

# Click the toggle again to expand
js_eval "
  (function() {
    var toggles = document.querySelectorAll('.border-l-2 > button');
    if (toggles.length > 0) toggles[0].click();
  })()
"
sleep 0.5

CONTENT_VISIBLE=$(js_eval "
  (function() {
    var blocks = document.querySelectorAll('.border-l-2');
    if (blocks.length === 0) return 'no-blocks';
    var first = blocks[0];
    var content = first.querySelector('.mt-1');
    return content !== null ? 'visible' : 'hidden';
  })()
")

if [ "$CONTENT_VISIBLE" = "visible" ]; then
  log_pass "Content restored after expand"
else
  log_fail "Content not restored after expand (got: ${CONTENT_VISIBLE})"
fi

# ===========================================================================
# TEST 8: Toolbar Buttons
# ===========================================================================
log_step "Test 8: Toolbar Buttons"

STATE=$(get_state)
assert_contains "$STATE" "Collapse all" "Toolbar has 'Collapse all' button"
assert_contains "$STATE" "Copy MD" "Toolbar has 'Copy MD' button"
assert_contains "$STATE" "Export HTML" "Toolbar has 'Export HTML' button"
assert_contains "$STATE" "Iron" "Toolbar has 'Iron' button"

# ===========================================================================
# TEST 9: No Hydration Errors
# ===========================================================================
log_step "Test 9: No Hydration Errors"

# Check for Next.js error overlay / toasts
HYDRATION_ERROR=$(js_eval "
  (function() {
    // Next.js dev overlay uses nextjs-portal
    var portal = document.querySelector('nextjs-portal');
    if (portal && portal.shadowRoot) {
      var toast = portal.shadowRoot.querySelector('[data-nextjs-toast]');
      if (toast) return toast.textContent || 'error-toast-found';
    }
    // Also check for the error overlay dialog
    if (portal && portal.shadowRoot) {
      var dialog = portal.shadowRoot.querySelector('[data-nextjs-dialog]');
      if (dialog) return dialog.textContent || 'error-dialog-found';
    }
    return 'clean';
  })()
")

if [ "$HYDRATION_ERROR" = "clean" ]; then
  log_pass "No Next.js hydration errors or error toasts"
else
  log_fail "Next.js error detected: ${HYDRATION_ERROR}"
fi

# Also check the console for hydration warnings via a JS flag
CONSOLE_ERRORS=$(js_eval "
  (function() {
    // Check if there's a #__next with data-reactroot that has mismatch
    var errors = [];
    // Next.js adds a global __NEXT_DATA__ — check for errors there
    if (window.__next_error__) errors.push('__next_error__');
    return errors.length > 0 ? errors.join(', ') : 'clean';
  })()
")

if [ "$CONSOLE_ERRORS" = "clean" ]; then
  log_pass "No console-level hydration markers"
else
  log_fail "Console errors detected: ${CONSOLE_ERRORS}"
fi

# ===========================================================================
# Summary
# ===========================================================================
echo ""
echo "==========================================="
TOTAL=$((PASSED + FAILED))
echo "  Results: ${PASSED}/${TOTAL} passed"
if [ "$FAILED" -gt 0 ]; then
  echo ""
  echo "  ${RED}Failures:${RESET}"
  for err in "${ERRORS[@]}"; do
    echo "    ${RED}- ${err}${RESET}"
  done
  echo "==========================================="
  exit 1
else
  echo "  ${GREEN}All tests passed!${RESET}"
  echo "==========================================="
  exit 0
fi
