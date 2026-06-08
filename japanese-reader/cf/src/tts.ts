/**
 * Text-to-speech via Google Gemini TTS (neural voices), on Cloudflare Workers.
 *
 * Replaces the browser Web Speech API (robotic, device-dependent system voices).
 * Same fetch-based approach + GEMINI_API_KEY as analyze.ts.
 *
 * Gemini TTS returns raw 16-bit PCM (audio/L16, 24kHz, mono). Browsers can't
 * play raw PCM, so we prepend a 44-byte WAV header and serve audio/wav.
 * Results are cached in KV by sha1(voice + text).
 */
import type { Env } from "./types.js";

const MODEL = "gemini-2.5-flash-preview-tts";
const TTS_URL = `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent`;

export const DEFAULT_VOICE = "Kore";
const SAMPLE_RATE = 24000;
const MAX_CHARS = 500;

async function sha1Hex(s: string): Promise<string> {
  const buf = await crypto.subtle.digest("SHA-1", new TextEncoder().encode(s));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

// Prepend a minimal 44-byte WAV/RIFF header to raw PCM (16-bit mono).
// Returns the backing ArrayBuffer (concrete type, plays nice with Response + KV).
function pcmToWav(pcm: Uint8Array, sampleRate = SAMPLE_RATE): ArrayBuffer {
  const numChannels = 1;
  const bitsPerSample = 16;
  const byteRate = (sampleRate * numChannels * bitsPerSample) / 8;
  const blockAlign = (numChannels * bitsPerSample) / 8;
  const dataSize = pcm.length;
  const buf = new ArrayBuffer(44 + dataSize);
  const view = new DataView(buf);
  const wstr = (off: number, s: string) => {
    for (let i = 0; i < s.length; i++) view.setUint8(off + i, s.charCodeAt(i));
  };
  wstr(0, "RIFF");
  view.setUint32(4, 36 + dataSize, true);
  wstr(8, "WAVE");
  wstr(12, "fmt ");
  view.setUint32(16, 16, true); // fmt chunk size
  view.setUint16(20, 1, true); // PCM
  view.setUint16(22, numChannels, true);
  view.setUint32(24, sampleRate, true);
  view.setUint32(28, byteRate, true);
  view.setUint16(32, blockAlign, true);
  view.setUint16(34, bitsPerSample, true);
  wstr(36, "data");
  view.setUint32(40, dataSize, true);
  new Uint8Array(buf, 44).set(pcm);
  return buf;
}

function b64ToBytes(b64: string): Uint8Array {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

// Some responses carry "audio/L16;codec=pcm;rate=24000" — pull the rate out if present.
function rateFromMime(mime: string | undefined): number {
  const m = mime?.match(/rate=(\d+)/);
  return m ? parseInt(m[1], 10) : SAMPLE_RATE;
}

/**
 * Return WAV bytes for the given Japanese text. Reads from KV cache when present,
 * otherwise synthesizes via Gemini TTS and caches the result.
 */
export async function synthesize(text: string, voice: string, env: Env): Promise<ArrayBuffer> {
  const trimmed = text.trim();
  if (!trimmed) throw new Error("empty text");
  if (trimmed.length > MAX_CHARS) throw new Error(`text too long (max ${MAX_CHARS} chars)`);

  const key = `tts:${voice}:${(await sha1Hex(`${voice}:${trimmed}`)).slice(0, 16)}`;

  const cached = await env.CACHE.get(key, "arrayBuffer");
  if (cached) return cached;

  const res = await fetch(TTS_URL, {
    method: "POST",
    headers: { "x-goog-api-key": env.GEMINI_API_KEY, "Content-Type": "application/json" },
    body: JSON.stringify({
      contents: [{ parts: [{ text: trimmed }] }],
      generationConfig: {
        responseModalities: ["AUDIO"],
        speechConfig: { voiceConfig: { prebuiltVoiceConfig: { voiceName: voice } } },
      },
    }),
  });

  if (!res.ok) {
    const body = await res.text();
    throw new Error(`Gemini TTS HTTP ${res.status}: ${body.slice(0, 300)}`);
  }

  const json = (await res.json()) as any;
  const part = json?.candidates?.[0]?.content?.parts?.[0];
  const inline = part?.inlineData ?? part?.inline_data;
  if (!inline?.data) {
    throw new Error(`Gemini TTS returned no audio: ${JSON.stringify(json).slice(0, 300)}`);
  }

  const pcm = b64ToBytes(inline.data);
  const wav = pcmToWav(pcm, rateFromMime(inline.mimeType ?? inline.mime_type));

  // KV stores ArrayBuffer; cache for a year (audio for given text never changes).
  await env.CACHE.put(key, wav, { expirationTtl: 31536000 });
  return wav;
}
