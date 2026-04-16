#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}▸${NC} $1"; }
warn()  { echo -e "${YELLOW}▸${NC} $1"; }
fail()  { echo -e "${RED}✗${NC} $1"; exit 1; }

cd "$(dirname "$0")"

echo ""
echo "  ╭──────────────────────────╮"
echo "  │     🌊 Undercurrent      │"
echo "  ╰──────────────────────────╯"
echo ""

# ── Node.js ──────────────────────────────────────────
if ! command -v node &>/dev/null; then
  warn "Node.js not found. Installing via Homebrew..."
  if command -v brew &>/dev/null; then
    brew install node
  else
    fail "Node.js not found and Homebrew not available.\n  Install Node.js 18+ from https://nodejs.org"
  fi
fi

NODE_VER=$(node -v | sed 's/v//' | cut -d. -f1)
if [ "$NODE_VER" -lt 18 ]; then
  fail "Node.js 18+ required (found v$(node -v)). Update: brew upgrade node"
fi
info "Node.js $(node -v) ✓"

# ── pnpm ─────────────────────────────────────────────
if ! command -v pnpm &>/dev/null; then
  warn "pnpm not found. Installing..."
  npm install -g pnpm
fi
info "pnpm $(pnpm -v) ✓"

# ── Claude CLI ───────────────────────────────────────
if ! command -v claude &>/dev/null; then
  warn "Claude CLI not found. Installing..."
  npm install -g @anthropic-ai/claude-code
  echo ""
  warn "Claude CLI installed. You need to login first:"
  echo "  Run: claude"
  echo "  Follow the browser login flow, then re-run ./start.sh"
  exit 0
fi
info "Claude CLI ✓"

# ── Dependencies ─────────────────────────────────────
if [ ! -d "node_modules" ]; then
  info "Installing dependencies..."
  pnpm install --frozen-lockfile 2>/dev/null || pnpm install
fi
info "Dependencies ✓"

# ── Launch ───────────────────────────────────────────
PORT=${PORT:-3000}
info "Starting on http://localhost:$PORT"
echo ""

# Open browser after a short delay
(sleep 3 && open "http://localhost:$PORT" 2>/dev/null || xdg-open "http://localhost:$PORT" 2>/dev/null) &

exec pnpm dev --port "$PORT"
