# Packaging Runbook — Undercurrent

## Pre-flight Checklist

Before building a release:

- [ ] Node.js installed (`node --version`)
- [ ] pnpm installed (`pnpm --version`)
- [ ] Claude CLI installed and authenticated (`claude --version`)
- [ ] All lint/type checks pass: `pnpm lint`
- [ ] Version number updated in `package.json` (see Version Bump below)
- [ ] Working tree is clean (`git status`)

## Version Bump

The version lives in one place: `package.json` (`"version": "X.Y.Z"`). electron-builder reads it automatically for DMG filenames and app metadata.

Update it before building:

```bash
# Edit package.json "version" field
# e.g., "0.1.0" → "0.2.0"
```

**TODO:** `tests/dmg-test.sh` has the version hardcoded in the default DMG path (line 29: `Undercurrent-0.1.0-arm64.dmg`). It should read the version dynamically from `package.json`. Until that's fixed, update the test script manually when bumping versions, or pass the DMG path explicitly:

```bash
bash tests/dmg-test.sh dist/Undercurrent-X.Y.Z-arm64.dmg
```

## Build

### Steps

```bash
# 1. Install dependencies
pnpm install

# 2. Build and package
pnpm dist
```

`pnpm dist` runs `scripts/build-app.js`, which does three things:

1. `next build` (standalone output) -- minimal self-contained Node.js server
2. Assembles standalone + static + public into `server-bundle/`
3. Runs `electron-builder` to produce `.app` and `.dmg`

### Output

Build artifacts land in `dist/`:

```
dist/Undercurrent-X.Y.Z-arm64.dmg   # Apple Silicon
dist/Undercurrent-X.Y.Z.dmg         # Intel (x64)
dist/mac-arm64/Undercurrent.app      # Unpacked app (arm64)
dist/mac/Undercurrent.app            # Unpacked app (x64)
```

Expect ~2-3 minutes for the full build. DMG size depends on bundled node_modules but is typically 150-250 MB.

## Install (Fresh)

### For the person building

Use the unpacked `.app` directly from `dist/mac-arm64/` for testing, or mount the DMG.

### For recipients

1. Double-click the `.dmg` file
2. Drag `Undercurrent.app` to `/Applications`
3. Eject the DMG

**First launch prerequisites:**

- Node.js must be installed on the machine (`brew install node` or from nodejs.org)
- Claude CLI must be installed and authenticated:
  ```bash
  npm install -g @anthropic-ai/claude-code
  claude   # run once to log in
  ```
- If the app isn't from a signed developer, macOS Gatekeeper will block it. Right-click the app and choose "Open", or go to System Settings > Privacy & Security > Allow.

The app checks for Claude CLI on startup and shows a dialog if it's missing.

## Upgrade (Replace Old Version)

```bash
# 1. Quit the running app
osascript -e 'quit app "Undercurrent"'

# 2. Wait a moment for the embedded server to shut down
sleep 2

# 3. Remove the old app
rm -rf /Applications/Undercurrent.app

# 4. Install the new version (mount DMG, drag to /Applications)

# 5. Launch and verify
open /Applications/Undercurrent.app
```

**Session persistence note:** Electron stores web data (localStorage, IndexedDB, cookies) in `~/Library/Application Support/Undercurrent/`. This directory survives app replacement, so previous sessions and settings persist across upgrades. This is different from browser-based apps where localStorage is tied to the browser profile -- here it's tied to the Electron app's user data directory.

## Uninstall

```bash
# 1. Quit the app
osascript -e 'quit app "Undercurrent"'

# 2. Kill any leftover server process on port 3456
lsof -ti:3456 | xargs kill -9 2>/dev/null

# 3. Remove the app
rm -rf /Applications/Undercurrent.app

# 4. (Optional) Remove Electron user data -- sessions, settings, cache
rm -rf ~/Library/Application\ Support/Undercurrent
```

## Testing

### Automated: DMG test suite

```bash
# Run against the default DMG for your architecture
bash tests/dmg-test.sh

# Or specify a DMG path explicitly
bash tests/dmg-test.sh dist/Undercurrent-X.Y.Z-arm64.dmg
```

The test suite (`tests/dmg-test.sh`) requires the `browser-use` CLI. It mounts the DMG, copies the app to a temp directory, launches it, and runs browser-based checks against the running app on port 3456. Cleanup is automatic.

What it verifies:
- DMG mounts and contains `.app`
- App copies and launches successfully
- Server starts on port 3456 within 45 seconds
- Welcome screen renders with expected elements
- Start button works, main UI loads
- Engine badge visible, question submission works
- Toolbar buttons present (Collapse all, Copy MD, Export HTML, Iron)
- Custom app icon is present and reasonably sized

### Manual smoke test

After install or upgrade:

- [ ] App launches without errors
- [ ] Claude CLI detection works (or shows install dialog if missing)
- [ ] Welcome screen appears, "Start Exploring" button works
- [ ] Submit a question, get a response from Claude
- [ ] Toolbar buttons (Collapse all, Copy MD, Export HTML, Iron) are functional
- [ ] Window resizes properly (minimum 600x400)
- [ ] Quit and relaunch -- previous data persists (if applicable)
- [ ] Menu bar shows "Undercurrent" with custom icon

## Known Issues

| Issue | Fix |
|-------|-----|
| "Undercurrent" can't be opened (macOS Gatekeeper) | Right-click > Open, or System Settings > Privacy & Security > Allow |
| Claude CLI not found | App shows install dialog. Install with `npm install -g @anthropic-ai/claude-code`, run `claude` once to authenticate, then relaunch |
| Auth expired | Run `claude` in terminal to re-authenticate |
| App launches but shows white screen | The standalone server takes a few seconds to start. Wait 5-10 seconds. If it persists, check if port 3456 is in use: `lsof -i:3456` |
| DMG test script uses hardcoded version | Pass the DMG path explicitly: `bash tests/dmg-test.sh dist/Undercurrent-X.Y.Z-arm64.dmg` |
| Build fails with symlink errors | The build uses `rsync --copy-links` to dereference pnpm symlinks. Warnings about vanished files during rsync are expected and harmless |
