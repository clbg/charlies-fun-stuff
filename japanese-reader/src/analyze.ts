/**
 * Analyze Japanese text into the JSON shape consumed by prototype.html.
 *
 * Mirrors the previous Python analyze.py:
 *   - Builds compact grammar registry from SQLite (cached on DB mtime)
 *   - Calls AWS Bedrock Converse with claude-sonnet-4-6 by default
 *   - Auto-fixes inner ASCII double-quotes inside CJK strings before JSON.parse
 *   - Walks the article and assigns token start/end offsets via String.indexOf
 *   - Caches by sha1(registry + text) under data/cache/
 *
 * CLI usage:
 *   pnpm analyze "今日は天気がいいです。"
 *   pnpm analyze -- --file input.txt --out data/samples/foo.json
 *   echo "..." | pnpm analyze
 */
import { createHash } from "crypto";
import {
  existsSync,
  mkdirSync,
  readFileSync,
  statSync,
  writeFileSync,
} from "fs";
import { resolve } from "path";
import {
  BedrockRuntimeClient,
  ConverseCommand,
} from "@aws-sdk/client-bedrock-runtime";
import { fromIni } from "@aws-sdk/credential-providers";
import { openDb, ROOT, DB_PATH } from "./db.js";

// ---------- Bedrock setup ----------

export const BEDROCK_MODELS: Record<string, string> = {
  sonnet: "us.anthropic.claude-sonnet-4-6",
  haiku: "us.anthropic.claude-3-5-haiku-20241022-v1:0",
  opus: "global.anthropic.claude-opus-4-7",
};
export const DEFAULT_MODEL = "sonnet";
const DEFAULT_REGION = "us-west-2";
const DEFAULT_PROFILE = process.env.AWS_PROFILE || "default";

// AWS_BEARER_TOKEN_BEDROCK takes priority over IAM profile when set, breaking
// auth for users on Amazon-internal ada/midway profiles. Strip it before
// constructing the client. Mirrors python analyze._setup_env().
function stripBearerToken(): void {
  delete process.env.AWS_BEARER_TOKEN_BEDROCK;
  delete process.env.ANTHROPIC_API_KEY;
}

let _client: BedrockRuntimeClient | null = null;
function getClient(): BedrockRuntimeClient {
  if (_client) return _client;
  const region = process.env.AWS_REGION || DEFAULT_REGION;
  const profile = DEFAULT_PROFILE;
  _client = new BedrockRuntimeClient({
    region,
    credentials: fromIni({ profile }),
  });
  return _client;
}

// ---------- Grammar registry (DB → compact prompt text) ----------

let _registryCache: { mtimeMs: number; text: string } | null = null;

export function loadGrammarRegistry(): string {
  if (!existsSync(DB_PATH)) {
    process.stderr.write(
      `[analyze] ${DB_PATH} not found — run server once + pnpm seed first.\n`
    );
    return "";
  }
  const mtimeMs = statSync(DB_PATH).mtimeMs;
  if (_registryCache && _registryCache.mtimeMs === mtimeMs) {
    return _registryCache.text;
  }

  const db = openDb();
  const rows = db
    .prepare(
      `SELECT canonical_id, display_form, level_hint, notes
       FROM grammar_points
       ORDER BY
         CASE level_hint
           WHEN 'N5' THEN 1 WHEN 'N4' THEN 2 WHEN 'N3' THEN 3
           WHEN 'N2' THEN 4 WHEN 'N1' THEN 5 ELSE 6
         END,
         canonical_id`
    )
    .all() as {
      canonical_id: string;
      display_form: string;
      level_hint: string | null;
      notes: string | null;
    }[];
  db.close();

  const lines = rows.map((r) => {
    let short = "";
    if (r.notes) {
      const m = r.notes.match(/\*\*Short\*\*:\s*(.+?)(?:\n|$)/);
      short = m ? m[1].trim() : r.notes.split("\n")[0].slice(0, 120);
    }
    return `${r.canonical_id} | ${r.display_form} | ${r.level_hint ?? "?"} | ${short}`;
  });

  const text = lines.join("\n");
  _registryCache = { mtimeMs, text };
  return text;
}

// ---------- System prompt ----------

export function buildSystemPrompt(registry: string): string {
  return `You are a Japanese language analyzer for an adaptive reader.

Use the grammar registry below as the source of canonical_id values. Each line is \`id | display_form | JLPT_level | short_explanation\`. Pick the closest match for each grammar pattern in the input. If nothing fits, use canonical_id "g_unregistered" and put a brief description in the explanation field.

<grammar_registry>
${registry}
</grammar_registry>

Output ONLY a JSON object (no markdown fences, no commentary) matching this schema:

{
  "title": "<short title in Japanese, can be invented>",
  "source": "<source if known, else 'user input'>",
  "sentences": [
    {
      "id": "s1",
      "ja": "<original sentence>",
      "zh": "<natural Chinese translation>",
      "tokens": [
        {
          "surface": "<as it appears in ja>",
          "dict_form": "<dictionary/lemma form>",
          "reading": "<hiragana reading>",
          "pos": "noun|verb|i_adjective|na_adjective|adverb|...",
          "meaning_zh": "<short Chinese gloss>"
        }
      ],
      "grammar": [
        {
          "canonical_id": "g_xxx",
          "display_form": "<canonical display form, e.g. Vている>",
          "meaning_zh": "<short Chinese meaning>",
          "explanation": "<one-line context-specific note>"
        }
      ]
    }
  ]
}

Rules:
- Skip particles, punctuation, and inflection-only morphemes from \`tokens\`. Only content words: nouns, verbs, adjectives, adverbs.
- For verbs/adjectives, dict_form is the lemma (進む, 強い, 走る) — not the inflected surface.
- DO NOT output \`start\` / \`end\` offsets. The pipeline computes them automatically from \`surface\`.
- For grammar, prefer canonical_ids from the registry. Use \`g_unregistered\` only if no reasonable match.
- Translate naturally to Chinese, not literal.
- Return one JSON object total, with all sentences from the input.
- IMPORTANT: Inside string values, NEVER use the ASCII double-quote character ". If you need to quote something inside a Chinese explanation, use 「」 or 『』 instead. Failing to follow this will break JSON parsing.
`;
}

// ---------- JSON repair ----------

// Match ASCII " sandwiched between CJK characters and replace with 」.
const QUOTE_FIX_RE = /(?<=[㐀-鿿　-〿])"|"(?=[㐀-鿿])/g;

export function repairInnerQuotes(s: string): string {
  return s.replace(QUOTE_FIX_RE, "」");
}

// ---------- Types ----------

export interface Token {
  surface: string;
  dict_form: string;
  reading?: string;
  pos?: string;
  meaning_zh?: string;
  start: number;
  end: number;
}
export interface GrammarRef {
  canonical_id: string;
  display_form?: string;
  meaning_zh?: string;
  explanation?: string;
}
export interface Sentence {
  id: string;
  ja: string;
  zh: string;
  tokens: Token[];
  grammar: GrammarRef[];
}
export interface Article {
  title?: string;
  source?: string;
  sentences: Sentence[];
}

// ---------- Bedrock call ----------

export async function callClaude(
  text: string,
  model: string = DEFAULT_MODEL
): Promise<Article> {
  stripBearerToken();
  const registry = loadGrammarRegistry();
  const modelId = BEDROCK_MODELS[model] ?? model;
  const client = getClient();

  const response = await client.send(
    new ConverseCommand({
      modelId,
      system: [{ text: buildSystemPrompt(registry) }],
      messages: [{ role: "user", content: [{ text }] }],
      inferenceConfig: { maxTokens: 8000, temperature: 0.2 },
    })
  );

  const block = response.output?.message?.content?.[0];
  if (!block || !("text" in block) || !block.text) {
    throw new Error("Bedrock returned empty content");
  }
  let raw = block.text.trim();
  raw = raw.replace(/^```(?:json)?\s*/, "").replace(/\s*```$/, "");

  try {
    return JSON.parse(raw) as Article;
  } catch {
    try {
      return JSON.parse(repairInnerQuotes(raw)) as Article;
    } catch (err) {
      process.stderr.write(`[analyze] LLM did not return valid JSON:\n${raw}\n`);
      throw err;
    }
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
        process.stderr.write(
          `[analyze] WARN: token ${JSON.stringify(surf)} not found in ${JSON.stringify(ja)}\n`
        );
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

export function warnUnregistered(article: Article): string[] {
  const seen = new Set<string>();
  for (const s of article.sentences ?? []) {
    for (const g of s.grammar ?? []) {
      if (g.canonical_id === "g_unregistered") {
        seen.add(g.display_form || g.explanation || "?");
      }
    }
  }
  if (seen.size > 0) {
    process.stderr.write(
      "[analyze] Unregistered grammar found (consider adding):\n"
    );
    for (const x of [...seen].sort()) process.stderr.write(`  - ${x}\n`);
  }
  return [...seen].sort();
}

// ---------- Cache ----------

const CACHE_DIR = resolve(ROOT, "data", "cache");

function cacheKey(text: string): string {
  const registryHash = createHash("sha1")
    .update(loadGrammarRegistry())
    .digest("hex")
    .slice(0, 8);
  const textHash = createHash("sha1").update(text).digest("hex").slice(0, 12);
  return `${registryHash}-${textHash}`;
}

function loadFromCache(key: string): Article | null {
  const p = resolve(CACHE_DIR, `${key}.json`);
  if (!existsSync(p)) return null;
  return JSON.parse(readFileSync(p, "utf-8")) as Article;
}

function saveToCache(key: string, data: Article): void {
  mkdirSync(CACHE_DIR, { recursive: true });
  writeFileSync(
    resolve(CACHE_DIR, `${key}.json`),
    JSON.stringify(data, null, 2),
    "utf-8"
  );
}

// ---------- Public entry ----------

export async function analyze(
  text: string,
  opts: { model?: string; useCache?: boolean } = {}
): Promise<Article> {
  const trimmed = text.trim();
  if (!trimmed) throw new Error("empty input");
  const useCache = opts.useCache !== false;
  const key = cacheKey(trimmed);
  if (useCache) {
    const cached = loadFromCache(key);
    if (cached) {
      process.stderr.write(`[analyze] cache hit (${key})\n`);
      return cached;
    }
  }
  process.stderr.write(`[analyze] calling Bedrock (${opts.model ?? DEFAULT_MODEL})...\n`);
  const raw = await callClaude(trimmed, opts.model ?? DEFAULT_MODEL);
  const article = assignOffsets(raw);
  warnUnregistered(article);
  if (useCache) saveToCache(key, article);
  return article;
}

// ---------- CLI ----------

async function main() {
  const args = process.argv.slice(2);
  let text = "";
  let outPath: string | null = null;
  let model = DEFAULT_MODEL;
  let useCache = true;

  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === "--file" || a === "-f") {
      text = readFileSync(args[++i], "utf-8");
    } else if (a === "--out" || a === "-o") {
      outPath = args[++i];
    } else if (a === "--model") {
      model = args[++i];
    } else if (a === "--no-cache") {
      useCache = false;
    } else if (!text) {
      text = a;
    }
  }
  if (!text) {
    text = await new Promise((res) => {
      let buf = "";
      process.stdin.on("data", (c) => (buf += c.toString()));
      process.stdin.on("end", () => res(buf));
    });
  }

  const article = await analyze(text, { model, useCache });
  const out = JSON.stringify(article, null, 2);
  if (outPath) {
    mkdirSync(resolve(outPath, ".."), { recursive: true });
    writeFileSync(outPath, out, "utf-8");
    process.stderr.write(`[analyze] wrote ${outPath}\n`);
  } else {
    process.stdout.write(out + "\n");
  }
}

const isMain =
  import.meta.url === `file://${process.argv[1]}` ||
  process.argv[1]?.endsWith("analyze.ts");
if (isMain) {
  main().catch((e) => {
    process.stderr.write(`[analyze] error: ${e.message}\n`);
    process.exit(1);
  });
}
