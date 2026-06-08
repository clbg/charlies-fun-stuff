import Database from "better-sqlite3";
import { fileURLToPath } from "url";
import { dirname, resolve } from "path";

const __dirname = dirname(fileURLToPath(import.meta.url));
export const ROOT = resolve(__dirname, "..");
export const DB_PATH = resolve(ROOT, "data", "familiarity.db");

export const SCHEMA = `
CREATE TABLE IF NOT EXISTS familiarity (
    item_type  TEXT NOT NULL,
    item_key   TEXT NOT NULL,
    score      INTEGER NOT NULL DEFAULT 0,
    seen_count INTEGER NOT NULL DEFAULT 0,
    last_seen  TEXT,
    notes      TEXT,
    PRIMARY KEY (item_type, item_key)
);

CREATE TABLE IF NOT EXISTS articles (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    title      TEXT,
    source     TEXT,
    raw_text   TEXT NOT NULL,
    json_data  TEXT NOT NULL,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS occurrences (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    article_id    INTEGER NOT NULL,
    sentence_idx  INTEGER NOT NULL,
    item_type     TEXT NOT NULL,
    item_key      TEXT NOT NULL,
    surface_form  TEXT NOT NULL,
    FOREIGN KEY (article_id) REFERENCES articles(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_occ_article ON occurrences(article_id);
CREATE INDEX IF NOT EXISTS idx_occ_item    ON occurrences(item_type, item_key);

CREATE TABLE IF NOT EXISTS vocab (
    dict_form   TEXT PRIMARY KEY,
    reading     TEXT,
    meaning_en  TEXT,
    meaning_zh  TEXT,
    jlpt_level  TEXT,
    pos         TEXT,
    notes       TEXT
);
CREATE INDEX IF NOT EXISTS idx_vocab_jlpt    ON vocab(jlpt_level);
CREATE INDEX IF NOT EXISTS idx_vocab_reading ON vocab(reading);

CREATE TABLE IF NOT EXISTS grammar_points (
    canonical_id  TEXT PRIMARY KEY,
    display_form  TEXT NOT NULL,
    meaning_zh    TEXT,
    function_tag  TEXT,
    level_hint    TEXT,
    aliases       TEXT,
    examples      TEXT,
    notes         TEXT
);
CREATE INDEX IF NOT EXISTS idx_grammar_level ON grammar_points(level_hint);
`;

export function openDb(): Database.Database {
  const db = new Database(DB_PATH);
  db.pragma("journal_mode = WAL");
  db.pragma("foreign_keys = ON");
  return db;
}

export function ensureSchema(db: Database.Database): void {
  db.exec(SCHEMA);
}

export function nowIso(): string {
  return new Date().toISOString();
}
