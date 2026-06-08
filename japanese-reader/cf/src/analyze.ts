/**
 * Analyze Japanese text into the Article JSON shape, on Cloudflare Workers.
 *
 * Ported from the original src/analyze.ts (AWS Bedrock) to Google Gemini 2.5 Flash:
 *   - Grammar registry built from D1 grammar_points (in-memory cached per isolate)
 *   - Gemini generateContent with native JSON mode (responseSchema) — far more
 *     reliable than Claude's "please don't emit quotes", so repairInnerQuotes is
 *     kept only as a last-resort fallback.
 *   - Token start/end offsets assigned via String.indexOf (LLM never emits them)
 *   - Cache by sha1(registry + text) in KV (replaces local data/cache/)
 */
import type { Article, Env } from "./types.js";

const MODEL = "gemini-2.5-flash";
const GEMINI_URL = `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent`;

// ---------- Grammar registry (D1 → compact prompt text) ----------

// Cached per isolate. Registry only changes when grammar_points is reseeded,
// which requires a redeploy/migration, so caching for the isolate lifetime is safe.
let _registryCache: string | null = null;

export async function loadGrammarRegistry(env: Env): Promise<string> {
  if (_registryCache !== null) return _registryCache;

  const { results } = await env.DB.prepare(
    `SELECT canonical_id, display_form, level_hint, notes
     FROM grammar_points
     ORDER BY
       CASE level_hint
         WHEN 'N5' THEN 1 WHEN 'N4' THEN 2 WHEN 'N3' THEN 3
         WHEN 'N2' THEN 4 WHEN 'N1' THEN 5 ELSE 6
       END,
       canonical_id`
  ).all<{
    canonical_id: string;
    display_form: string;
    level_hint: string | null;
    notes: string | null;
  }>();

  const lines = results.map((r) => {
    let short = "";
    if (r.notes) {
      const m = r.notes.match(/\*\*Short\*\*:\s*(.+?)(?:\n|$)/);
      short = m ? m[1].trim() : r.notes.split("\n")[0].slice(0, 120);
    }
    return `${r.canonical_id} | ${r.display_form} | ${r.level_hint ?? "?"} | ${short}`;
  });

  _registryCache = lines.join("\n");
  return _registryCache;
}

// ---------- System prompt ----------

export function buildSystemPrompt(registry: string): string {
  return `You are a Japanese language analyzer for an adaptive reader.

Use the grammar registry below as the source of canonical_id values. Each line is \`id | display_form | JLPT_level | short_explanation\`. Pick the closest match for each grammar pattern in the input. If nothing fits, use canonical_id "g_unregistered" and put a brief description in the explanation field.

<grammar_registry>
${registry}
</grammar_registry>

Output a JSON object matching the provided schema.

Rules:
- Skip particles, punctuation, and inflection-only morphemes from \`tokens\`. Only content words: nouns, verbs, adjectives, adverbs.
- For verbs/adjectives, dict_form is the lemma (進む, 強い, 走る) — not the inflected surface.
- DO NOT output \`start\` / \`end\` offsets. The pipeline computes them automatically from \`surface\`.
- For grammar, prefer canonical_ids from the registry. Use \`g_unregistered\` only if no reasonable match.
- Translate naturally to Chinese, not literal.
- Return one JSON object total, with all sentences from the input.`;
}

// Native JSON-mode response schema. Gemini constrains output to this shape,
// which eliminates the markdown-fence and inner-quote problems entirely.
const RESPONSE_SCHEMA = {
  type: "object",
  properties: {
    title: { type: "string" },
    source: { type: "string" },
    sentences: {
      type: "array",
      items: {
        type: "object",
        properties: {
          id: { type: "string" },
          ja: { type: "string" },
          zh: { type: "string" },
          tokens: {
            type: "array",
            items: {
              type: "object",
              properties: {
                surface: { type: "string" },
                dict_form: { type: "string" },
                reading: { type: "string" },
                pos: { type: "string" },
                meaning_zh: { type: "string" },
              },
              required: ["surface", "dict_form"],
            },
          },
          grammar: {
            type: "array",
            items: {
              type: "object",
              properties: {
                canonical_id: { type: "string" },
                display_form: { type: "string" },
                meaning_zh: { type: "string" },
                explanation: { type: "string" },
              },
              required: ["canonical_id"],
            },
          },
        },
        required: ["id", "ja", "zh", "tokens", "grammar"],
      },
    },
  },
  required: ["sentences"],
};

// ---------- JSON repair (fallback) ----------

const QUOTE_FIX_RE = /(?<=[㐀-鿿　-〿])"|"(?=[㐀-鿿])/g;
export function repairInnerQuotes(s: string): string {
  return s.replace(QUOTE_FIX_RE, "」");
}

// ---------- Gemini call ----------

export async function callGemini(text: string, env: Env): Promise<Article> {
  const registry = await loadGrammarRegistry(env);
  const res = await fetch(GEMINI_URL, {
    method: "POST",
    headers: {
      "x-goog-api-key": env.GEMINI_API_KEY,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      systemInstruction: { parts: [{ text: buildSystemPrompt(registry) }] },
      contents: [{ role: "user", parts: [{ text }] }],
      generationConfig: {
        responseMimeType: "application/json",
        responseSchema: RESPONSE_SCHEMA,
        temperature: 0.2,
        maxOutputTokens: 8000,
      },
    }),
  });

  if (!res.ok) {
    const body = await res.text();
    throw new Error(`Gemini HTTP ${res.status}: ${body.slice(0, 500)}`);
  }

  const json = (await res.json()) as any;
  const raw = json?.candidates?.[0]?.content?.parts?.[0]?.text;
  if (!raw) {
    throw new Error(`Gemini returned no content: ${JSON.stringify(json).slice(0, 500)}`);
  }

  try {
    return JSON.parse(raw) as Article;
  } catch {
    // Fallback: should be rare under JSON mode.
    return JSON.parse(repairInnerQuotes(raw)) as Article;
  }
}

// ---------- Offsets ----------

export function assignOffsets(article: Article): Article {
  for (const s of article.sentences ?? []) {
    let cursor = 0;
    const ja = s.ja;
    for (const t of s.tokens ?? []) {
      const surf = t.surface ?? "";
      let idx = ja.indexOf(surf, cursor);
      if (idx < 0) idx = ja.indexOf(surf);
      if (idx < 0) {
        t.start = -1;
        t.end = -1;
      } else {
        t.start = idx;
        t.end = idx + surf.length;
        cursor = t.end;
      }
    }
  }
  return article;
}

// ---------- Cache (KV) ----------

async function sha1Hex(s: string): Promise<string> {
  const data = new TextEncoder().encode(s);
  const buf = await crypto.subtle.digest("SHA-1", data);
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function cacheKey(text: string, registry: string): Promise<string> {
  const rh = (await sha1Hex(registry)).slice(0, 8);
  const th = (await sha1Hex(text)).slice(0, 12);
  return `analyze:${rh}-${th}`;
}

// ---------- Public entry ----------

export async function analyze(
  text: string,
  env: Env,
  opts: { useCache?: boolean } = {}
): Promise<Article> {
  const trimmed = text.trim();
  if (!trimmed) throw new Error("empty input");
  const useCache = opts.useCache !== false;
  const registry = await loadGrammarRegistry(env);
  const key = await cacheKey(trimmed, registry);

  if (useCache) {
    const cached = await env.CACHE.get(key, "json");
    if (cached) return cached as Article;
  }

  const raw = await callGemini(trimmed, env);
  const article = assignOffsets(raw);

  if (useCache) {
    await env.CACHE.put(key, JSON.stringify(article));
  }
  return article;
}
