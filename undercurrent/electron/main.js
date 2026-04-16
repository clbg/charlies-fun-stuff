const { app, BrowserWindow, dialog } = require("electron");
const { spawn, execSync } = require("child_process");
const path = require("path");
const net = require("net");
const fs = require("fs");
const os = require("os");

const PORT = 3456;
let mainWindow = null;
let serverProcess = null;

// ── Resolve full PATH from user's login shell ────────
// Electron.app on macOS launches with a minimal PATH (/usr/bin:/bin:/usr/sbin:/sbin).
// We need to source the user's shell to get the real PATH that includes
// nvm, homebrew, npm globals, etc.
function resolveShellEnv() {
  try {
    const shell = process.env.SHELL || "/bin/zsh";
    // Ask the login shell to print its PATH
    const fullPath = execSync(`${shell} -ilc 'echo "__PATH__=$PATH"'`, {
      encoding: "utf-8",
      timeout: 5000,
    });
    const match = fullPath.match(/__PATH__=(.+)/);
    if (match) {
      process.env.PATH = match[1];
    }
  } catch {
    // Fallback: manually append common locations
    const home = os.homedir();
    const extra = [
      "/usr/local/bin",
      "/opt/homebrew/bin",
      `${home}/.nvm/current/bin`,
      `${home}/.volta/bin`,
      `${home}/.npm-global/bin`,
      `${home}/.local/bin`,
    ].filter((p) => fs.existsSync(p));
    process.env.PATH = `${extra.join(":")}:${process.env.PATH}`;
  }
}

// ── Helpers ──────────────────────────────────────────

function findBin(name) {
  try {
    return execSync(`which ${name}`, { encoding: "utf-8" }).trim();
  } catch {
    return null;
  }
}

function waitForPort(port, ms = 30_000) {
  return new Promise((resolve, reject) => {
    const deadline = Date.now() + ms;
    (function tick() {
      const s = new net.Socket();
      s.once("connect", () => { s.destroy(); resolve(); });
      s.once("error", () => {
        s.destroy();
        Date.now() > deadline ? reject(new Error("timeout")) : setTimeout(tick, 200);
      });
      s.connect(port, "127.0.0.1");
    })();
  });
}

// ── App lifecycle ────────────────────────────────────

app.whenReady().then(async () => {
  // 0. Fix PATH
  resolveShellEnv();

  // 1. Check Claude CLI
  const claudePath = findBin("claude");
  if (!claudePath) {
    const { response } = await dialog.showMessageBox({
      type: "warning",
      title: "Claude CLI Required",
      message: "Undercurrent needs the Claude CLI.",
      detail:
        "Install:\n  npm install -g @anthropic-ai/claude-code\n\n" +
        "Then run `claude` once in your terminal to log in.\n\n" +
        `Current PATH:\n${process.env.PATH.split(":").slice(0, 5).join("\n")}...`,
      buttons: ["Quit", "Continue Anyway"],
    });
    if (response === 0) return app.quit();
  }

  // 2. Kill stale server on our port (from crashed previous run)
  try {
    execSync(`lsof -ti:${PORT} | xargs kill -9`, { stdio: "ignore" });
  } catch { /* nothing on that port, fine */ }

  // 3. Find node
  const nodePath = findBin("node") || "node";

  // 3. Start Next.js standalone server
  // In packaged app: server-bundle is inside app.asar (or app/ with asar:false)
  const standaloneDir = path.join(app.getAppPath(), "server-bundle");
  const serverJs = path.join(standaloneDir, "server.js");
  const modulesDir = path.join(standaloneDir, "node_modules");
  serverProcess = spawn(nodePath, [serverJs], {
    cwd: standaloneDir,
    env: {
      ...process.env,
      PORT: String(PORT),
      HOSTNAME: "127.0.0.1",
      NODE_ENV: "production",
      NODE_PATH: modulesDir,
    },
    stdio: ["ignore", "pipe", "pipe"],
  });
  serverProcess.stdout.on("data", (d) => console.log(d.toString().trimEnd()));
  serverProcess.stderr.on("data", (d) => console.error(d.toString().trimEnd()));

  // 4. Wait for server
  try {
    await waitForPort(PORT);
  } catch {
    dialog.showErrorBox("Start Failed", "The server didn't come up. Check logs.");
    return app.quit();
  }

  // 5. Open window
  mainWindow = new BrowserWindow({
    width: 900,
    height: 700,
    minWidth: 600,
    minHeight: 400,
    title: "Undercurrent",
    titleBarStyle: "hiddenInset",
    trafficLightPosition: { x: 16, y: 16 },
    webPreferences: { nodeIntegration: false, contextIsolation: true },
  });
  mainWindow.loadURL(`http://127.0.0.1:${PORT}`);
  mainWindow.on("closed", () => { mainWindow = null; });
});

app.on("window-all-closed", () => {
  if (serverProcess) { serverProcess.kill(); serverProcess = null; }
  app.quit();
});
