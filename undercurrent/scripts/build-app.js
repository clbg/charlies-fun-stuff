#!/usr/bin/env node
/**
 * Build Undercurrent as a desktop app (.app / .dmg).
 *
 * Steps:
 *   1. `next build` with output: "standalone"
 *   2. Assemble standalone into server-bundle/ (asar: false, inside app)
 *   3. Run electron-builder
 */

const { execSync } = require("child_process");
const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "..");
const STANDALONE = path.join(ROOT, ".next", "standalone");
const STATIC_SRC = path.join(ROOT, ".next", "static");
const PUBLIC_SRC = path.join(ROOT, "public");
const BUNDLE = path.join(ROOT, "server-bundle");

function run(cmd) {
  console.log(`\n▸ ${cmd}`);
  execSync(cmd, { cwd: ROOT, stdio: "inherit" });
}

// 1. Next.js build
run("npx next build");

// 2. Assemble standalone into server-bundle/
if (fs.existsSync(BUNDLE)) {
  fs.rmSync(BUNDLE, { recursive: true });
}
fs.mkdirSync(BUNDLE, { recursive: true });

// Copy standalone output (dereference all symlinks from pnpm)
console.log("\n▸ Copying standalone server (dereferencing symlinks)...");
try {
  execSync(`rsync -a --copy-links --ignore-errors "${STANDALONE}/" "${BUNDLE}/"`, { stdio: "inherit" });
} catch {
  // rsync may warn about vanished files, OK
}

// Static files must live at .next/static
const staticDest = path.join(BUNDLE, ".next", "static");
fs.mkdirSync(staticDest, { recursive: true });
fs.cpSync(STATIC_SRC, staticDest, { recursive: true });

// Public files
if (fs.existsSync(PUBLIC_SRC)) {
  fs.cpSync(PUBLIC_SRC, path.join(BUNDLE, "public"), { recursive: true });
}

console.log("▸ Standalone server assembled in server-bundle/");

// 3. electron-builder
run("npx electron-builder --mac --config electron-builder.yml");

console.log("\n✓ Done! Check dist/ for the .app");
