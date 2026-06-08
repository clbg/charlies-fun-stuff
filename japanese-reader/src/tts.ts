/**
 * Text-to-speech via AWS Polly (neural Japanese voices).
 *
 * Synthesizes Japanese text to mp3, cached on disk by sha1(text + voice).
 * Same AWS-profile auth approach as analyze.ts (ada/midway, no API key).
 *
 * Japanese neural voices available on this account: Kazuha, Tomoko (female),
 * Takumi (male). Default = Kazuha (newest neural voice).
 */
import { createHash } from "crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "fs";
import { resolve } from "path";
import {
  PollyClient,
  SynthesizeSpeechCommand,
  type Engine,
  type VoiceId,
} from "@aws-sdk/client-polly";
import { fromIni } from "@aws-sdk/credential-providers";
import { ROOT } from "./db.js";

const DEFAULT_REGION = "us-west-2";
const DEFAULT_PROFILE = process.env.AWS_PROFILE || "default";
export const DEFAULT_VOICE = "Kazuha";
export const JA_NEURAL_VOICES = ["Kazuha", "Tomoko", "Takumi"] as const;

const AUDIO_CACHE_DIR = resolve(ROOT, "data", "audio_cache");

let _client: PollyClient | null = null;
function getClient(): PollyClient {
  if (_client) return _client;
  // Same gotcha as Bedrock: a bearer token env var would shadow the IAM profile.
  delete process.env.AWS_BEARER_TOKEN_BEDROCK;
  _client = new PollyClient({
    region: process.env.AWS_REGION || DEFAULT_REGION,
    credentials: fromIni({ profile: DEFAULT_PROFILE }),
  });
  return _client;
}

function cacheKey(text: string, voice: string): string {
  return createHash("sha1").update(`${voice}:${text}`).digest("hex").slice(0, 16);
}

function cachePath(key: string): string {
  return resolve(AUDIO_CACHE_DIR, `${key}.mp3`);
}

/**
 * Return mp3 bytes for the given Japanese text. Reads from disk cache when
 * present, otherwise synthesizes via Polly and writes the cache.
 */
export async function synthesize(
  text: string,
  voice: string = DEFAULT_VOICE
): Promise<Buffer> {
  const trimmed = text.trim();
  if (!trimmed) throw new Error("empty text");

  const key = cacheKey(trimmed, voice);
  const path = cachePath(key);
  if (existsSync(path)) {
    return readFileSync(path);
  }

  const client = getClient();
  const res = await client.send(
    new SynthesizeSpeechCommand({
      Text: trimmed,
      VoiceId: voice as VoiceId,
      Engine: "neural" as Engine,
      OutputFormat: "mp3",
      LanguageCode: "ja-JP",
    })
  );

  if (!res.AudioStream) throw new Error("Polly returned no audio stream");
  // AudioStream is a Node Readable (SdkStreamMixin) — transform to bytes.
  const bytes = await res.AudioStream.transformToByteArray();
  const buf = Buffer.from(bytes);

  mkdirSync(AUDIO_CACHE_DIR, { recursive: true });
  writeFileSync(path, buf);
  return buf;
}
