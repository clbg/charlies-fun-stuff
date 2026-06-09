/**
 * Daily article job: fetch a long Japanese article from Wikipedia, analyze it,
 * save to D1, and pre-warm TTS for every sentence (so playback is instant).
 *
 * Source: ja.wikipedia.org MediaWiki API (CC BY-SA, free REST, no scraping block).
 * NHK News Web Easy went paywalled (2025-10) and NHK blocks scrapers, so Wikipedia
 * is the stable long-form source. Topics are broad (history/science/culture).
 *
 * Triggered by the Cron Trigger (scheduled handler) and the POST /api/daily route.
 */
import type { Env, Article } from "./types.js";
import { analyze } from "./analyze.js";
import { synthesize, DEFAULT_VOICE } from "./tts.js";

const WIKI_API = "https://ja.wikipedia.org/w/api.php";
const MIN_CHARS = 300; // skip stubs
const MAX_CHARS = 700; // a solid multi-paragraph read that stays within token limits
const MAX_TRIES = 8;

interface DailyResult {
  article_id: number | null;
  title: string;
  source_url: string;
  chars: number;
  sentences: number;
  tts_warmed: number;
  tts_failed: number;
}

// Fetch one random main-namespace article's plain-text extract.
async function fetchRandomArticle(): Promise<{ title: string; text: string } | null> {
  const url =
    `${WIKI_API}?action=query&format=json&origin=*` +
    `&generator=random&grnnamespace=0&grnlimit=1` +
    `&prop=extracts&explaintext=1&exsectionformat=plain&exchars=${MAX_CHARS}`;
  const res = await fetch(url, { headers: { "User-Agent": "japanese-reader/1.0 (personal study tool)" } });
  if (!res.ok) return null;
  const json = (await res.json()) as any;
  const pages = json?.query?.pages;
  if (!pages) return null;
  const page = Object.values(pages)[0] as any;
  const text = (page?.extract ?? "").trim();
  const title = page?.title ?? "";
  if (!text) return null;
  return { title, text };
}

// Wikipedia extracts include section noise and very long single lines; tidy it
// into clean sentence-bearing prose for the analyzer.
function cleanText(raw: string): string {
  return raw
    .replace(/={2,}.*?={2,}/g, "") // strip "== 見出し ==" headers
    .replace(/\n+/g, "")
    .replace(/\s+/g, "")
    .trim();
}

// Split text into chunks of <= maxChars, breaking only at sentence ends (。！？).
function chunkBySentence(text: string, maxChars: number): string[] {
  const sentences = text.match(/[^。！？]*[。！？]/g) ?? [text];
  const chunks: string[] = [];
  let cur = "";
  for (const s of sentences) {
    if (cur.length + s.length > maxChars && cur) {
      chunks.push(cur);
      cur = "";
    }
    cur += s;
  }
  if (cur.trim()) chunks.push(cur);
  return chunks;
}

export async function runDaily(env: Env): Promise<DailyResult> {
  // Pick a random article that's long enough.
  let picked: { title: string; text: string } | null = null;
  for (let i = 0; i < MAX_TRIES; i++) {
    const a = await fetchRandomArticle();
    if (a && cleanText(a.text).length >= MIN_CHARS) {
      picked = { title: a.title, text: cleanText(a.text) };
      break;
    }
  }
  if (!picked) throw new Error("could not find a long-enough Wikipedia article after retries");

  // Trim to MAX_CHARS at a sentence boundary so analyze stays snappy.
  let text = picked.text;
  if (text.length > MAX_CHARS) {
    const cut = text.lastIndexOf("。", MAX_CHARS);
    text = text.slice(0, cut > 0 ? cut + 1 : MAX_CHARS);
  }

  const sourceUrl = `https://ja.wikipedia.org/wiki/${encodeURIComponent(picked.title)}`;

  // Analyze in small chunks and merge. One big call on a long article truncates
  // (MAX_TOKENS → invalid JSON) or times out; ~300-char chunks stay in Gemini's
  // fast, reliable zone (same size as the short passages that always worked).
  const chunks = chunkBySentence(text, 300);
  const merged: Article = { title: picked.title, source: sourceUrl, sentences: [] };
  for (const chunk of chunks) {
    const part = await analyze(chunk, env);
    for (const s of part.sentences ?? []) {
      s.id = String(merged.sentences.length); // re-index across chunks
      merged.sentences.push(s);
    }
  }
  if (!merged.sentences.length) throw new Error("analyze produced no sentences");
  const article = merged;

  const insert = await env.DB.prepare(
    `INSERT INTO articles (title, source, raw_text, json_data) VALUES (?, ?, ?, ?)`
  )
    .bind(article.title, sourceUrl, text, JSON.stringify(article))
    .run();
  const articleId = Number(insert.meta.last_row_id);

  const occ = env.DB.prepare(
    `INSERT INTO occurrences (article_id, sentence_idx, item_type, item_key, surface_form)
     VALUES (?, ?, ?, ?, ?)`
  );
  const occBatch: D1PreparedStatement[] = [];
  (article.sentences ?? []).forEach((s, sIdx) => {
    for (const t of s.tokens ?? []) occBatch.push(occ.bind(articleId, sIdx, "word", t.dict_form, t.surface));
    for (const g of s.grammar ?? [])
      occBatch.push(occ.bind(articleId, sIdx, "grammar", g.canonical_id, g.display_form || g.canonical_id));
  });
  if (occBatch.length) await env.DB.batch(occBatch);

  // Pre-warm TTS for every sentence → playback is an instant KV cache hit.
  let warmed = 0;
  let failed = 0;
  for (const s of article.sentences ?? []) {
    try {
      await synthesize(s.ja, DEFAULT_VOICE, env);
      warmed++;
    } catch {
      failed++; // a single TTS miss shouldn't fail the whole job
    }
  }

  return {
    article_id: articleId,
    title: article.title ?? picked.title,
    source_url: sourceUrl,
    chars: text.length,
    sentences: article.sentences?.length ?? 0,
    tts_warmed: warmed,
    tts_failed: failed,
  };
}
