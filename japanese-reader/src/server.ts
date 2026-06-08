/**
 * Local Express server for Japanese Reader.
 *
 * Mirrors python server.py:
 *   GET  /                          → serves prototype.html
 *   GET  /api/health
 *   GET  /api/familiarity
 *   POST /api/familiarity           {type, key, score}
 *   POST /api/familiarity/import    {"word:foo": 3, ...}
 *   POST /api/familiarity/reset
 *   GET  /api/articles
 *   GET  /api/articles/:id
 *   DEL  /api/articles/:id
 *   POST /api/analyze               {text, save?}
 *   GET  /api/tts?text=...&voice=   → audio/mpeg (Polly neural, disk-cached)
 *   GET  /api/stats
 *
 * Run:
 *   pnpm server                          # http://localhost:5151
 *   pnpm dev                             # tsx watch (auto-reload)
 */
import express from "express";
import { readFileSync } from "fs";
import { resolve } from "path";
import { openDb, ensureSchema, ROOT, nowIso } from "./db.js";
import { analyze } from "./analyze.js";
import { synthesize, DEFAULT_VOICE, JA_NEURAL_VOICES } from "./tts.js";

const PORT = parseInt(process.argv[2] ?? process.env.PORT ?? "5151", 10);
const PROTOTYPE_PATH = resolve(ROOT, "prototype.html");

// One-time schema ensure
{
  const db = openDb();
  ensureSchema(db);
  db.close();
}

const app = express();
app.use(express.json({ limit: "5mb" }));

// Permissive CORS for local dev (file:// origin or other ports during testing).
app.use((_req, res, next) => {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Headers", "Content-Type");
  res.set("Access-Control-Allow-Methods", "GET,POST,DELETE,OPTIONS");
  if (_req.method === "OPTIONS") {
    res.sendStatus(204);
    return;
  }
  next();
});

// ---------- Static ----------

app.get("/", (_req, res) => {
  res.type("text/html").send(readFileSync(PROTOTYPE_PATH, "utf-8"));
});

app.get("/api/health", (_req, res) => {
  res.json({ ok: true, ts: nowIso() });
});

// ---------- Familiarity ----------

app.get("/api/familiarity", (_req, res) => {
  const db = openDb();
  try {
    const rows = db
      .prepare("SELECT item_type, item_key, score FROM familiarity")
      .all() as { item_type: string; item_key: string; score: number }[];
    const out: Record<string, number> = {};
    for (const r of rows) out[`${r.item_type}:${r.item_key}`] = r.score;
    res.json(out);
  } finally {
    db.close();
  }
});

app.post("/api/familiarity", (req, res) => {
  const { type, key, score } = req.body ?? {};
  if (!type || !key || typeof score !== "number") {
    res.status(400).json({ error: "type, key, score required" });
    return;
  }
  const v = Math.max(0, Math.min(5, Math.floor(score)));
  const db = openDb();
  try {
    db.prepare(
      `INSERT INTO familiarity (item_type, item_key, score, last_seen)
       VALUES (?, ?, ?, ?)
       ON CONFLICT(item_type, item_key) DO UPDATE SET
         score = excluded.score,
         last_seen = excluded.last_seen`
    ).run(type, key, v, nowIso());
    res.json({ ok: true, score: v });
  } finally {
    db.close();
  }
});

app.post("/api/familiarity/import", (req, res) => {
  const body = (req.body ?? {}) as Record<string, number>;
  const db = openDb();
  let n = 0;
  try {
    const stmt = db.prepare(
      `INSERT INTO familiarity (item_type, item_key, score, last_seen)
       VALUES (?, ?, ?, ?)
       ON CONFLICT(item_type, item_key) DO UPDATE SET
         score = excluded.score,
         last_seen = excluded.last_seen`
    );
    const ts = nowIso();
    const tx = db.transaction(() => {
      for (const [composite, score] of Object.entries(body)) {
        const idx = composite.indexOf(":");
        if (idx < 0) continue;
        const t = composite.slice(0, idx);
        const k = composite.slice(idx + 1);
        const v = Math.max(0, Math.min(5, Math.floor(Number(score))));
        stmt.run(t, k, v, ts);
        n++;
      }
    });
    tx();
    res.json({ ok: true, imported: n });
  } finally {
    db.close();
  }
});

app.post("/api/familiarity/reset", (_req, res) => {
  const db = openDb();
  try {
    db.exec("DELETE FROM familiarity");
    res.json({ ok: true });
  } finally {
    db.close();
  }
});

// ---------- Articles ----------

app.get("/api/articles", (_req, res) => {
  const db = openDb();
  try {
    const rows = db
      .prepare(
        "SELECT id, title, source, created_at FROM articles ORDER BY id DESC"
      )
      .all();
    res.json(rows);
  } finally {
    db.close();
  }
});

app.get("/api/articles/:id", (req, res) => {
  const id = parseInt(req.params.id, 10);
  const db = openDb();
  try {
    const row = db
      .prepare(
        "SELECT id, title, source, raw_text, json_data, created_at FROM articles WHERE id = ?"
      )
      .get(id) as
      | {
          id: number;
          title: string;
          source: string;
          raw_text: string;
          json_data: string;
          created_at: string;
        }
      | undefined;
    if (!row) {
      res.status(404).json({ error: "not found" });
      return;
    }
    res.json({
      id: row.id,
      title: row.title,
      source: row.source,
      raw_text: row.raw_text,
      created_at: row.created_at,
      data: JSON.parse(row.json_data),
    });
  } finally {
    db.close();
  }
});

app.delete("/api/articles/:id", (req, res) => {
  const id = parseInt(req.params.id, 10);
  const db = openDb();
  try {
    db.prepare("DELETE FROM articles WHERE id = ?").run(id);
    res.json({ ok: true });
  } finally {
    db.close();
  }
});

// ---------- Analyze ----------

app.post("/api/analyze", async (req, res) => {
  const text = String(req.body?.text ?? "").trim();
  if (!text) {
    res.status(400).json({ error: "empty text" });
    return;
  }
  const save = req.body?.save !== false;

  let article;
  try {
    article = await analyze(text);
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e);
    res.status(500).json({ error: msg });
    return;
  }

  let articleId: number | null = null;
  if (save) {
    const db = openDb();
    try {
      const insertArticle = db.prepare(
        `INSERT INTO articles (title, source, raw_text, json_data) VALUES (?, ?, ?, ?)`
      );
      const insertOcc = db.prepare(
        `INSERT INTO occurrences (article_id, sentence_idx, item_type, item_key, surface_form)
         VALUES (?, ?, ?, ?, ?)`
      );
      const tx = db.transaction(() => {
        const result = insertArticle.run(
          article.title || text.slice(0, 30),
          article.source || "user input",
          text,
          JSON.stringify(article)
        );
        articleId = Number(result.lastInsertRowid);
        const sentences = article.sentences ?? [];
        sentences.forEach((s, sIdx) => {
          for (const t of s.tokens ?? []) {
            insertOcc.run(articleId, sIdx, "word", t.dict_form, t.surface);
          }
          for (const g of s.grammar ?? []) {
            insertOcc.run(
              articleId,
              sIdx,
              "grammar",
              g.canonical_id,
              g.display_form || g.canonical_id
            );
          }
        });
      });
      tx();
    } finally {
      db.close();
    }
  }

  res.json({ article_id: articleId, data: article });
});

// ---------- TTS ----------

app.get("/api/tts", async (req, res) => {
  const text = String(req.query.text ?? "").trim();
  if (!text) {
    res.status(400).json({ error: "text query param required" });
    return;
  }
  if (text.length > 500) {
    res.status(400).json({ error: "text too long (max 500 chars)" });
    return;
  }
  let voice = String(req.query.voice ?? DEFAULT_VOICE);
  if (!(JA_NEURAL_VOICES as readonly string[]).includes(voice)) {
    voice = DEFAULT_VOICE;
  }
  try {
    const mp3 = await synthesize(text, voice);
    res.set("Content-Type", "audio/mpeg");
    res.set("Cache-Control", "public, max-age=31536000, immutable");
    res.send(mp3);
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e);
    res.status(500).json({ error: msg });
  }
});

// ---------- Stats ----------

app.get("/api/stats", (_req, res) => {
  const db = openDb();
  try {
    const total_articles = (
      db.prepare("SELECT COUNT(*) AS n FROM articles").get() as { n: number }
    ).n;
    const unique_words = (
      db
        .prepare(
          "SELECT COUNT(DISTINCT item_key) AS n FROM occurrences WHERE item_type='word'"
        )
        .get() as { n: number }
    ).n;
    const unique_grammar = (
      db
        .prepare(
          "SELECT COUNT(DISTINCT item_key) AS n FROM occurrences WHERE item_type='grammar'"
        )
        .get() as { n: number }
    ).n;
    const scored = (
      db.prepare("SELECT COUNT(*) AS n FROM familiarity").get() as {
        n: number;
      }
    ).n;
    const unknown = (
      db
        .prepare("SELECT COUNT(*) AS n FROM familiarity WHERE score < 3")
        .get() as { n: number }
    ).n;
    res.json({
      articles: total_articles,
      unique_words_seen: unique_words,
      unique_grammar_seen: unique_grammar,
      scored_items: scored,
      unknown_items: unknown,
    });
  } finally {
    db.close();
  }
});

// ---------- Boot ----------

app.listen(PORT, "127.0.0.1", () => {
  console.log("");
  console.log("  Japanese Reader server (TS)");
  console.log(`  → http://localhost:${PORT}`);
  console.log("");
});
