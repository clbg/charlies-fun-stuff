/**
 * Seed reference tables in familiarity.db.
 *   - vocab          ← study-japanese-vocabulary/jlpt_vocab.csv (~7900)
 *   - grammar_points ← data/hanabira_grammar/*.json (828, CC by hanabira.org)
 *
 * Idempotent. Familiarity / articles / occurrences are NOT touched.
 *
 * Usage:
 *   pnpm seed
 *   pnpm seed -- --vocab
 *   pnpm seed -- --grammar
 */
import { readFileSync, existsSync, readdirSync } from "fs";
import { resolve } from "path";
import { parse } from "csv-parse/sync";
import { openDb, ensureSchema, ROOT, DB_PATH } from "./db.js";

const HANABIRA_DIR = resolve(ROOT, "data", "hanabira_grammar");
const DEFAULT_CSV = resolve(
  ROOT,
  "..",
  "study-japanese-vocabulary",
  "jlpt_vocab.csv"
);
const LEVELS = ["N5", "N4", "N3", "N2", "N1"] as const;

// ---------- Vocab ----------

interface VocabRow {
  Original: string;
  Furigana: string;
  English: string;
  "JLPT Level": string;
}

function seedVocab(csvPath: string): number {
  if (!existsSync(csvPath)) {
    console.error(`[seed] vocab CSV not found: ${csvPath}`);
    return 0;
  }
  const raw = readFileSync(csvPath, "utf-8");
  const records: VocabRow[] = parse(raw, {
    columns: true,
    skip_empty_lines: true,
    trim: true,
  });

  const db = openDb();
  ensureSchema(db);
  const stmt = db.prepare(
    `INSERT INTO vocab (dict_form, reading, meaning_en, meaning_zh, jlpt_level, pos, notes)
     VALUES (@dict_form, @reading, @meaning_en, @meaning_zh, @jlpt_level, @pos, @notes)
     ON CONFLICT(dict_form) DO UPDATE SET
       reading    = COALESCE(excluded.reading,    reading),
       meaning_en = COALESCE(excluded.meaning_en, meaning_en),
       jlpt_level = COALESCE(excluded.jlpt_level, jlpt_level)`
  );

  let n = 0;
  const tx = db.transaction(() => {
    for (const r of records) {
      const dict = (r.Original || "").trim();
      if (!dict) continue;
      stmt.run({
        dict_form: dict,
        reading: (r.Furigana || "").trim() || null,
        meaning_en: (r.English || "").trim() || null,
        meaning_zh: null,
        jlpt_level: (r["JLPT Level"] || "").trim() || null,
        pos: null,
        notes: null,
      });
      n++;
    }
  });
  tx();
  db.close();
  return n;
}

// ---------- Grammar (Hanabira) ----------

interface HanabiraExample {
  jp?: string;
  romaji?: string;
  en?: string;
}
interface HanabiraEntry {
  title: string;
  short_explanation?: string;
  long_explanation?: string;
  formation?: string;
  examples?: HanabiraExample[];
}
interface NormalizedEntry extends HanabiraEntry {
  level: string;
  canonical_id: string;
}

function slugifyTitle(title: string): string {
  // Hanabira titles look like "～かもしれない (~kamoshirenai)" — take romaji in parens.
  const m = title.match(/\(([^)]+)\)\s*$/);
  let s = (m ? m[1] : title).toLowerCase();
  s = s.replace(/[～~、,。.]/g, "");
  s = s.replace(/[^a-z0-9]+/g, "_").replace(/_+/g, "_");
  s = s.replace(/^_|_$/g, "");
  return s ? `g_${s}` : "g_unnamed";
}

function assignCanonicalIds(entries: NormalizedEntry[]): void {
  const baseFor = entries.map((e) => slugifyTitle(e.title));
  const counts = new Map<string, number>();
  for (const b of baseFor) counts.set(b, (counts.get(b) ?? 0) + 1);

  const seen = new Map<string, number>();
  entries.forEach((e, i) => {
    const base = baseFor[i];
    let cid = (counts.get(base) ?? 0) === 1 ? base : `${base}_${e.level.toLowerCase()}`;
    const cur = (seen.get(cid) ?? 0) + 1;
    seen.set(cid, cur);
    if (cur > 1) cid = `${cid}_${cur}`;
    e.canonical_id = cid;
  });
}

function loadHanabira(): NormalizedEntry[] {
  if (!existsSync(HANABIRA_DIR)) {
    console.error(`[seed] hanabira dir not found: ${HANABIRA_DIR}`);
    return [];
  }
  const out: NormalizedEntry[] = [];
  for (const level of LEVELS) {
    const path = resolve(
      HANABIRA_DIR,
      `grammar_ja_${level}_full_alphabetical_0001.json`
    );
    if (!existsSync(path)) continue;
    const data: HanabiraEntry[] = JSON.parse(readFileSync(path, "utf-8"));
    for (const raw of data) {
      out.push({ ...raw, level, canonical_id: "" });
    }
  }
  assignCanonicalIds(out);
  return out;
}

function buildNotes(e: HanabiraEntry): string {
  const parts: string[] = [];
  if (e.short_explanation) parts.push(`**Short**: ${e.short_explanation}`);
  if (e.formation) parts.push(`**Formation**: ${e.formation}`);
  if (e.long_explanation) parts.push(`**Long**: ${e.long_explanation}`);
  parts.push("\n_Source: hanabira.org (CC)_");
  return parts.join("\n\n");
}

function formatExamples(examples: HanabiraExample[] | undefined): string {
  if (!examples?.length) return "[]";
  const out = examples.slice(0, 6).map((ex) => ({
    ja: ex.jp ?? "",
    en: ex.en ?? "",
    romaji: ex.romaji ?? "",
    zh: "",
  }));
  return JSON.stringify(out);
}

function seedGrammar(): number {
  const entries = loadHanabira();
  if (!entries.length) return 0;

  const db = openDb();
  ensureSchema(db);
  const stmt = db.prepare(
    `INSERT INTO grammar_points
       (canonical_id, display_form, meaning_zh, function_tag, level_hint, aliases, examples, notes)
     VALUES (@canonical_id, @display_form, @meaning_zh, @function_tag, @level_hint, @aliases, @examples, @notes)
     ON CONFLICT(canonical_id) DO UPDATE SET
       display_form = excluded.display_form,
       level_hint   = excluded.level_hint,
       examples     = excluded.examples,
       notes        = excluded.notes`
  );

  const tx = db.transaction(() => {
    for (const e of entries) {
      const display =
        e.title.replace(/\s*\([^)]+\)\s*$/, "").trim() || e.title;
      stmt.run({
        canonical_id: e.canonical_id,
        display_form: display,
        meaning_zh: null,
        function_tag: null,
        level_hint: e.level,
        aliases: "[]",
        examples: formatExamples(e.examples),
        notes: buildNotes(e),
      });
    }
  });
  tx();
  db.close();
  return entries.length;
}

// ---------- CLI ----------

function main() {
  const args = process.argv.slice(2);
  const onlyVocab = args.includes("--vocab");
  const onlyGrammar = args.includes("--grammar");
  const csvIdx = args.indexOf("--csv");
  const csvPath = csvIdx >= 0 ? args[csvIdx + 1] : DEFAULT_CSV;

  const doVocab = onlyVocab || !onlyGrammar;
  const doGrammar = onlyGrammar || !onlyVocab;

  console.log(`[seed] DB: ${DB_PATH}`);
  if (doVocab) {
    const n = seedVocab(csvPath);
    console.log(`[seed] vocab: ${n} rows`);
  }
  if (doGrammar) {
    const n = seedGrammar();
    console.log(`[seed] grammar_points: ${n} rows`);
  }
}

main();
