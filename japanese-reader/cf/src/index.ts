/**
 * Japanese Reader Worker: Hono API + React SPA (served via ASSETS binding).
 *
 * Ported from the original Express server.ts. All endpoints are now async
 * against D1. TTS (/api/tts, Polly) is dropped — the React frontend uses the
 * browser Web Speech API. Auth is handled at the edge by Cloudflare Access.
 *
 * Endpoints:
 *   GET  /api/health
 *   GET  /api/familiarity
 *   POST /api/familiarity            {type, key, score}
 *   POST /api/familiarity/import     {"word:foo": 3, ...}
 *   POST /api/familiarity/reset
 *   GET  /api/articles
 *   GET  /api/articles/:id
 *   DEL  /api/articles/:id
 *   POST /api/analyze                {text, save?}
 *   GET  /api/stats
 *   *  → React SPA (ASSETS)
 */
import { Hono } from "hono";
import type { Env, Article } from "./types.js";
import { analyze } from "./analyze.js";
import { synthesize, DEFAULT_VOICE } from "./tts.js";

// Gemini prebuilt voices usable for TTS (subset; all multilingual).
const TTS_VOICES = ["Kore", "Puck", "Charon", "Aoede", "Fenrir"];

const app = new Hono<{ Bindings: Env }>();

const nowIso = () => new Date().toISOString();

// ---------- Health ----------

app.get("/api/health", (c) => c.json({ ok: true, ts: nowIso() }));

// ---------- Familiarity ----------

app.get("/api/familiarity", async (c) => {
  const { results } = await c.env.DB.prepare(
    "SELECT item_type, item_key, score FROM familiarity"
  ).all<{ item_type: string; item_key: string; score: number }>();
  const out: Record<string, number> = {};
  for (const r of results) out[`${r.item_type}:${r.item_key}`] = r.score;
  return c.json(out);
});

app.post("/api/familiarity", async (c) => {
  const { type, key, score } = (await c.req.json().catch(() => ({}))) as {
    type?: string;
    key?: string;
    score?: number;
  };
  if (!type || !key || typeof score !== "number") {
    return c.json({ error: "type, key, score required" }, 400);
  }
  const v = Math.max(0, Math.min(5, Math.floor(score)));
  await c.env.DB.prepare(
    `INSERT INTO familiarity (item_type, item_key, score, last_seen)
     VALUES (?, ?, ?, ?)
     ON CONFLICT(item_type, item_key) DO UPDATE SET
       score = excluded.score, last_seen = excluded.last_seen`
  )
    .bind(type, key, v, nowIso())
    .run();
  return c.json({ ok: true, score: v });
});

app.post("/api/familiarity/import", async (c) => {
  const body = ((await c.req.json().catch(() => ({}))) ?? {}) as Record<string, number>;
  const ts = nowIso();
  const stmt = c.env.DB.prepare(
    `INSERT INTO familiarity (item_type, item_key, score, last_seen)
     VALUES (?, ?, ?, ?)
     ON CONFLICT(item_type, item_key) DO UPDATE SET
       score = excluded.score, last_seen = excluded.last_seen`
  );
  const batch: D1PreparedStatement[] = [];
  for (const [composite, score] of Object.entries(body)) {
    const idx = composite.indexOf(":");
    if (idx < 0) continue;
    const t = composite.slice(0, idx);
    const k = composite.slice(idx + 1);
    const v = Math.max(0, Math.min(5, Math.floor(Number(score))));
    batch.push(stmt.bind(t, k, v, ts));
  }
  if (batch.length) await c.env.DB.batch(batch);
  return c.json({ ok: true, imported: batch.length });
});

app.post("/api/familiarity/reset", async (c) => {
  await c.env.DB.prepare("DELETE FROM familiarity").run();
  return c.json({ ok: true });
});

// ---------- Articles ----------

app.get("/api/articles", async (c) => {
  const { results } = await c.env.DB.prepare(
    "SELECT id, title, source, created_at FROM articles ORDER BY id DESC"
  ).all();
  return c.json(results);
});

app.get("/api/articles/:id", async (c) => {
  const id = parseInt(c.req.param("id"), 10);
  const row = await c.env.DB.prepare(
    "SELECT id, title, source, raw_text, json_data, created_at FROM articles WHERE id = ?"
  )
    .bind(id)
    .first<{
      id: number;
      title: string;
      source: string;
      raw_text: string;
      json_data: string;
      created_at: string;
    }>();
  if (!row) return c.json({ error: "not found" }, 404);
  return c.json({
    id: row.id,
    title: row.title,
    source: row.source,
    raw_text: row.raw_text,
    created_at: row.created_at,
    data: JSON.parse(row.json_data),
  });
});

app.delete("/api/articles/:id", async (c) => {
  const id = parseInt(c.req.param("id"), 10);
  await c.env.DB.prepare("DELETE FROM articles WHERE id = ?").bind(id).run();
  return c.json({ ok: true });
});

// ---------- Analyze ----------

app.post("/api/analyze", async (c) => {
  const body = (await c.req.json().catch(() => ({}))) as { text?: string; save?: boolean };
  const text = String(body.text ?? "").trim();
  if (!text) return c.json({ error: "empty text" }, 400);
  const save = body.save !== false;

  let article: Article;
  try {
    article = await analyze(text, c.env);
  } catch (e) {
    return c.json({ error: e instanceof Error ? e.message : String(e) }, 500);
  }

  let articleId: number | null = null;
  if (save) {
    const result = await c.env.DB.prepare(
      `INSERT INTO articles (title, source, raw_text, json_data) VALUES (?, ?, ?, ?)`
    )
      .bind(
        article.title || text.slice(0, 30),
        article.source || "user input",
        text,
        JSON.stringify(article)
      )
      .run();
    articleId = Number(result.meta.last_row_id);

    // Insert occurrences in one batch.
    const ins = c.env.DB.prepare(
      `INSERT INTO occurrences (article_id, sentence_idx, item_type, item_key, surface_form)
       VALUES (?, ?, ?, ?, ?)`
    );
    const batch: D1PreparedStatement[] = [];
    (article.sentences ?? []).forEach((s, sIdx) => {
      for (const t of s.tokens ?? []) {
        batch.push(ins.bind(articleId, sIdx, "word", t.dict_form, t.surface));
      }
      for (const g of s.grammar ?? []) {
        batch.push(ins.bind(articleId, sIdx, "grammar", g.canonical_id, g.display_form || g.canonical_id));
      }
    });
    if (batch.length) await c.env.DB.batch(batch);
  }

  return c.json({ article_id: articleId, data: article });
});

// ---------- TTS ----------

app.get("/api/tts", async (c) => {
  const text = (c.req.query("text") ?? "").trim();
  if (!text) return c.json({ error: "text query param required" }, 400);
  let voice = c.req.query("voice") ?? DEFAULT_VOICE;
  if (!TTS_VOICES.includes(voice)) voice = DEFAULT_VOICE;
  try {
    const wav = await synthesize(text, voice, c.env);
    return new Response(wav, {
      status: 200,
      headers: {
        "Content-Type": "audio/wav",
        "Cache-Control": "public, max-age=31536000, immutable",
      },
    });
  } catch (e) {
    return c.json({ error: e instanceof Error ? e.message : String(e) }, 500);
  }
});

// ---------- Stats ----------

app.get("/api/stats", async (c) => {
  const q = (sql: string) => c.env.DB.prepare(sql).first<{ n: number }>();
  const [articles, words, grammar, scored, unknown] = await Promise.all([
    q("SELECT COUNT(*) AS n FROM articles"),
    q("SELECT COUNT(DISTINCT item_key) AS n FROM occurrences WHERE item_type='word'"),
    q("SELECT COUNT(DISTINCT item_key) AS n FROM occurrences WHERE item_type='grammar'"),
    q("SELECT COUNT(*) AS n FROM familiarity"),
    q("SELECT COUNT(*) AS n FROM familiarity WHERE score < 3"),
  ]);
  return c.json({
    articles: articles?.n ?? 0,
    unique_words_seen: words?.n ?? 0,
    unique_grammar_seen: grammar?.n ?? 0,
    scored_items: scored?.n ?? 0,
    unknown_items: unknown?.n ?? 0,
  });
});

// ---------- Static SPA fallback ----------
// Anything not matched above is served from the ASSETS binding (React SPA).
app.all("*", (c) => c.env.ASSETS.fetch(c.req.raw));

export default app;
