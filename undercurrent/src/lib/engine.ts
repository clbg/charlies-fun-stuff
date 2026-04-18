import { spawn, type ChildProcess } from "child_process";
import { streamFromBedrock, isBedrockAvailable } from "./bedrock-engine";

const activeProcesses = new Map<string, ChildProcess>();
const activeAbortControllers = new Map<string, AbortController>();

// ── Backend detection (cached) ───────────────────────

let _backend: "bedrock" | "cli" | null = null;

export async function detectBackend(): Promise<"bedrock" | "cli"> {
  if (_backend) return _backend;
  if (await isBedrockAvailable()) {
    _backend = "bedrock";
  } else {
    _backend = "cli";
  }
  return _backend;
}

// ── Unified stream entry point ───────────────────────

export async function* streamFromEngine(
  engine: "claude",
  prompt: string,
  nodeId: string,
  options?: { model?: "haiku" | "sonnet" }
): AsyncGenerator<string> {
  const backend = await detectBackend();

  if (backend === "bedrock") {
    const ac = new AbortController();
    activeAbortControllers.set(nodeId, ac);
    try {
      for await (const chunk of streamFromBedrock(prompt, options)) {
        if (ac.signal.aborted) break;
        yield chunk;
      }
    } finally {
      activeAbortControllers.delete(nodeId);
    }
  } else {
    yield* streamFromCLI(engine, prompt, nodeId, options);
  }
}

// ── CLI backend ──────────────────────────────────────

async function* streamFromCLI(
  engine: "claude",
  prompt: string,
  nodeId: string,
  options?: { model?: "haiku" | "sonnet" }
): AsyncGenerator<string> {
  const args = engineArgs(engine, prompt, options);
  const bin = "claude";

  const proc = spawn(bin, args, {
    stdio: ["ignore", "pipe", "pipe"],
  });

  activeProcesses.set(nodeId, proc);

  try {
    const stream = proc.stdout!;
    const decoder = new TextDecoder();

    for await (const chunk of stream) {
      yield decoder.decode(chunk as Buffer, { stream: true });
    }

    await new Promise<void>((resolve, reject) => {
      proc.on("close", (code) => {
        if (code !== 0) {
          reject(new Error(`${bin} exited with code ${code}`));
        } else {
          resolve();
        }
      });
    });
  } finally {
    activeProcesses.delete(nodeId);
  }
}

function engineArgs(
  engine: "claude",
  prompt: string,
  options?: { model?: "haiku" | "sonnet" }
): string[] {
  switch (engine) {
    case "claude": {
      const args = ["-p", prompt];
      if (options?.model) args.push("--model", options.model);
      return args;
    }
  }
}

// ── Abort ────────────────────────────────────────────

export function abortEngine(nodeId: string): boolean {
  const proc = activeProcesses.get(nodeId);
  if (proc) {
    proc.kill("SIGTERM");
    activeProcesses.delete(nodeId);
    return true;
  }
  const ac = activeAbortControllers.get(nodeId);
  if (ac) {
    ac.abort();
    activeAbortControllers.delete(nodeId);
    return true;
  }
  return false;
}

export function abortAll(): void {
  for (const [id, proc] of activeProcesses) {
    proc.kill("SIGTERM");
    activeProcesses.delete(id);
  }
  for (const [id, ac] of activeAbortControllers) {
    ac.abort();
    activeAbortControllers.delete(id);
  }
}

process.on("SIGTERM", abortAll);
process.on("SIGINT", abortAll);
