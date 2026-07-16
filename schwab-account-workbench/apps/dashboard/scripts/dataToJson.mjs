#!/usr/bin/env node
// Convert the generated vault data.js (window.SCHWAB_* = "csv string") into a
// single portfolio.json the React app bundles at build time. Keeps the Python
// pipeline and the original viewer untouched — we just re-shape existing data.
//
// Events (dividends + earnings): preferred source is SCHWAB_API_EVENTS_CSV, which
// schwab_workbench.api_refresh now emits. If a data.js predates that (no events yet), we
// derive dividend events on the fly from the latest sanitized JSON so the
// calendar still shows something before the next live refresh.
//
// Usage: node scripts/dataToJson.mjs [path/to/data.js]

import { readFileSync, writeFileSync, mkdirSync, readdirSync } from "node:fs";
import { dirname, resolve, join } from "node:path";
import { fileURLToPath } from "node:url";
import vm from "node:vm";

const here = dirname(fileURLToPath(import.meta.url));
const defaultVaultRoot = process.env.CHARLIE_VAULT_ROOT
  || (process.env.G_DRIVE_AUTO_SYNC_PATH ? join(process.env.G_DRIVE_AUTO_SYNC_PATH, "CharlieObsidianVault") : join(process.env.HOME, "Library/CloudStorage/GoogleDrive-charlie.pengcheng@gmail.com/My Drive/Autosync/CharlieObsidianVault"));
const historyRoot = process.env.SCHWAB_HISTORY_ROOT
  ? resolve(process.env.SCHWAB_HISTORY_ROOT)
  : join(defaultVaultRoot, "Investment/Portfolio/SchwabHistory");
const dataJs = process.argv[2] || join(historyRoot, "viewer/data.js");
const outPath = resolve(here, "../src/data/portfolio.json");

const source = readFileSync(dataJs, "utf8");
const sandbox = { window: {} };
vm.createContext(sandbox);
vm.runInContext(source, sandbox, { filename: "data.js" });
const w = sandbox.window;

function csvEscape(v) {
  const s = String(v ?? "");
  return /[",\n]/.test(s) ? `"${s.replaceAll('"', '""')}"` : s;
}

function toCsv(rows, cols) {
  return [cols.join(","), ...rows.map((r) => cols.map((c) => csvEscape(r[c])).join(","))].join("\n");
}

const isoDate = (v) => (v ? String(v).slice(0, 10) : null);

// Fallback: derive dividend events from the newest sanitized JSON payload.
function deriveEventsFromSanitized() {
  const dir = join(historyRoot, "processed");
  let files;
  try {
    files = readdirSync(dir).filter((f) => /^schwab-api-raw-sanitized-.*\.json$/.test(f)).sort();
  } catch {
    return "";
  }
  if (!files.length) return "";
  const payload = JSON.parse(readFileSync(join(dir, files[files.length - 1]), "utf8"));
  const date = (payload.captured_at || "").slice(0, 10) || "unknown";
  const held = new Set();
  for (const acct of payload.accounts || []) {
    for (const p of acct.securitiesAccount?.positions || []) {
      const ins = p.instrument || {};
      if (ins.symbol) held.add(ins.symbol);
      if (ins.underlyingSymbol) held.add(ins.underlyingSymbol);
    }
  }
  const rows = [];
  for (const [symbol, q] of Object.entries(payload.quotes || {})) {
    if (held.size && !held.has(symbol)) continue;
    const f = q.fundamental || {};
    const amt = f.divAmount || 0;
    const exDate = isoDate(f.nextDivExDate);
    const payDate = isoDate(f.nextDivPayDate);
    if (exDate) rows.push({ snapshot_date: date, symbol, event_type: "dividend_ex", event_date: exDate, detail: amt ? `Ex-dividend · $${amt}/sh` : "Ex-dividend" });
    if (payDate) rows.push({ snapshot_date: date, symbol, event_type: "dividend_pay", event_date: payDate, detail: amt ? `Dividend pay · $${amt}/sh` : "Dividend pay" });
  }
  rows.sort((a, b) => a.event_date.localeCompare(b.event_date) || a.symbol.localeCompare(b.symbol));
  return rows.length ? toCsv(rows, ["snapshot_date", "symbol", "event_type", "event_date", "detail"]) : "";
}

const events = w.SCHWAB_API_EVENTS_CSV ?? deriveEventsFromSanitized();

const out = {
  meta: w.SCHWAB_DATA_META ?? { date: "unknown", source: "schwab_trader_api" },
  accounts: w.SCHWAB_API_ACCOUNTS_CSV ?? "",
  positions: w.SCHWAB_API_POSITIONS_CSV ?? "",
  quotes: w.SCHWAB_API_QUOTES_CSV ?? "",
  prices: w.SCHWAB_API_PRICES_CSV ?? "",
  apiTransactions: w.SCHWAB_API_TRANSACTIONS_CSV ?? "",
  legacyTransactions: w.SCHWAB_LEGACY_TX_CSV ?? "",
  optionChains: w.SCHWAB_API_OPTION_CHAINS_CSV ?? "",
  optionRisk: w.SCHWAB_API_OPTION_RISK_CSV ?? "",
  events,
  sourceStatus: w.SCHWAB_SOURCE_STATUS_CSV ?? "",
  secFilings: w.SCHWAB_SEC_FILINGS_CSV ?? "",
  macroEvents: w.SCHWAB_MACRO_EVENTS_CSV ?? "",
  cryptoPrices: w.SCHWAB_CRYPTO_PRICES_CSV ?? "",
  analystRatings: w.SCHWAB_ANALYST_RATINGS_CSV ?? "",
  newsHeadlines: w.SCHWAB_NEWS_HEADLINES_CSV ?? "",
};

if (!out.accounts) {
  console.error("dataToJson: no SCHWAB_API_ACCOUNTS_CSV found in", dataJs);
  process.exit(1);
}

mkdirSync(dirname(outPath), { recursive: true });
writeFileSync(outPath, JSON.stringify(out));
const kb = (JSON.stringify(out).length / 1024).toFixed(0);
const evCount = events ? events.trim().split("\n").length - 1 : 0;
console.log(`dataToJson: wrote ${outPath} (${kb} KB, snapshot ${out.meta.date}, ${evCount} events)`);
