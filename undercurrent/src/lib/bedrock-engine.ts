import {
  BedrockRuntimeClient,
  ConverseStreamCommand,
} from "@aws-sdk/client-bedrock-runtime";
import { fromIni } from "@aws-sdk/credential-providers";
import { readFileSync } from "fs";
import { join } from "path";
import { homedir } from "os";

// ── Read Claude CLI config for AWS settings ──────────

interface ClaudeConfig {
  profile: string;
  region: string;
  baseModel: string;
}

let _config: ClaudeConfig | null = null;

function getConfig(): ClaudeConfig {
  if (_config) return _config;

  let profile = "default";
  let region = "us-west-2";
  let baseModel = "us.anthropic.claude-sonnet-4-5-20250514-v1:0";

  try {
    const raw = readFileSync(
      join(homedir(), ".claude", "settings.json"),
      "utf-8"
    );
    const settings = JSON.parse(raw);
    const env = settings.env || {};

    if (env.AWS_PROFILE) profile = env.AWS_PROFILE;
    if (env.AWS_REGION) region = env.AWS_REGION;
    if (settings.model) baseModel = settings.model;
  } catch {
    // Use defaults
  }

  _config = { profile, region, baseModel };
  return _config;
}

// ── Model ID mapping ─────────────────────────────────

const BEDROCK_MODELS: Record<string, string> = {
  haiku: "us.anthropic.claude-3-5-haiku-20241022-v1:0",
  sonnet: "us.anthropic.claude-sonnet-4-6",
};

// Default model for root questions (opus-level)
const DEFAULT_MODEL = "us.anthropic.claude-sonnet-4-6";

function resolveModelId(model?: "haiku" | "sonnet"): string {
  if (model && BEDROCK_MODELS[model]) return BEDROCK_MODELS[model];
  return DEFAULT_MODEL;
}

// ── Client singleton ─────────────────────────────────

let _client: BedrockRuntimeClient | null = null;

function getClient(): BedrockRuntimeClient {
  if (_client) return _client;
  const cfg = getConfig();
  _client = new BedrockRuntimeClient({
    region: cfg.region,
    credentials: fromIni({ profile: cfg.profile }),
  });
  return _client;
}

// ── Check if Bedrock is available ────────────────────

export async function isBedrockAvailable(): Promise<boolean> {
  try {
    const cfg = getConfig();
    if (!cfg.profile) return false;
    // Try to resolve credentials
    const creds = fromIni({ profile: cfg.profile });
    await creds();
    return true;
  } catch {
    return false;
  }
}

// ── Streaming inference ──────────────────────────────

export async function* streamFromBedrock(
  prompt: string,
  options?: { model?: "haiku" | "sonnet" }
): AsyncGenerator<string> {
  const client = getClient();
  const modelId = resolveModelId(options?.model);

  const command = new ConverseStreamCommand({
    modelId,
    messages: [
      {
        role: "user",
        content: [{ text: prompt }],
      },
    ],
    inferenceConfig: {
      maxTokens: 4096,
    },
  });

  const response = await client.send(command);

  if (response.stream) {
    for await (const event of response.stream) {
      if (event.contentBlockDelta?.delta?.text) {
        yield event.contentBlockDelta.delta.text;
      }
    }
  }
}
