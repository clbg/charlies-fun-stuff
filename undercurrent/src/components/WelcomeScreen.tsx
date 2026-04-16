"use client";

import { useState, useEffect } from "react";
import type { Engine } from "@/lib/types";

interface EngineOption {
  id: Engine;
  name: string;
  description: string;
  available: boolean;
}

interface WelcomeScreenProps {
  onStart: (engine: Engine) => void;
}

const engines: Omit<EngineOption, "available">[] = [
  {
    id: "claude",
    name: "Claude",
    description: "Anthropic Claude via CLI — deep reasoning, long context",
  },
];

export function WelcomeScreen({ onStart }: WelcomeScreenProps) {
  const [selected, setSelected] = useState<Engine>("claude");
  const [availability, setAvailability] = useState<Record<string, boolean>>({});
  const [backend, setBackend] = useState<string>("");
  const [checking, setChecking] = useState(true);

  useEffect(() => {
    fetch("/api/engines")
      .then((r) => r.json())
      .then((data) => {
        setAvailability(data);
        setBackend(data.backend || "cli");
        const firstAvail = engines.find((e) => data[e.id]);
        if (firstAvail) setSelected(firstAvail.id);
        setChecking(false);
      })
      .catch(() => setChecking(false));
  }, []);

  const selectedAvailable = availability[selected];

  return (
    <div className="flex flex-1 flex-col items-center justify-center bg-zinc-50 px-6 pt-8 dark:bg-zinc-950">
      <div className="w-full max-w-md">
        {/* Logo / title */}
        <div className="mb-10 text-center">
          <div className="mb-4 text-5xl">〰</div>
          <h1 className="text-2xl font-semibold text-zinc-900 dark:text-zinc-100">
            Undercurrent
          </h1>
          <p className="mt-2 text-sm text-zinc-500 dark:text-zinc-400">
            Select text. Branch deeper. Explore without losing context.
          </p>
        </div>

        {/* Engine selection */}
        <div className="mb-6">
          <label className="mb-2 block text-xs font-medium uppercase tracking-wider text-zinc-400">
            Engine
          </label>
          <div className="space-y-2">
            {engines.map((eng) => {
              const avail = checking ? null : availability[eng.id];
              return (
                <button
                  key={eng.id}
                  onClick={() => setSelected(eng.id)}
                  className={`w-full rounded-xl border px-4 py-3 text-left transition-all ${
                    selected === eng.id
                      ? "border-zinc-900 bg-white shadow-sm dark:border-zinc-400 dark:bg-zinc-900"
                      : "border-zinc-200 bg-white/50 hover:border-zinc-300 dark:border-zinc-800 dark:bg-zinc-900/50"
                  }`}
                >
                  <div className="flex items-center justify-between">
                    <span className="font-medium text-zinc-900 dark:text-zinc-100">
                      {eng.name}
                    </span>
                    {checking ? (
                      <span className="text-xs text-zinc-400">checking...</span>
                    ) : avail ? (
                      <span className="text-xs text-green-600 dark:text-green-400">ready</span>
                    ) : (
                      <span className="text-xs text-red-500">not found</span>
                    )}
                  </div>
                  <p className="mt-1 text-xs text-zinc-500">
                    {eng.description}
                    {!checking && avail && backend && (
                      <span className="ml-1 text-zinc-400">
                        via {backend === "bedrock" ? "AWS Bedrock (fast)" : "CLI"}
                      </span>
                    )}
                  </p>
                </button>
              );
            })}
          </div>
        </div>

        {/* Not available hint */}
        {!checking && !selectedAvailable && (
          <div className="mb-4 rounded-lg border border-amber-200 bg-amber-50 px-4 py-3 text-xs text-amber-800 dark:border-amber-800 dark:bg-amber-950 dark:text-amber-300">
            <p className="font-medium">Claude CLI not detected</p>
            <p className="mt-1">
              Install: <code className="font-mono">npm install -g @anthropic-ai/claude-code</code>
            </p>
            <p>Then run <code className="font-mono">claude</code> once to log in.</p>
          </div>
        )}

        {/* Start */}
        <button
          onClick={() => onStart(selected)}
          className="w-full rounded-xl bg-zinc-900 px-4 py-3 font-medium text-white transition-colors hover:bg-zinc-700 dark:bg-zinc-100 dark:text-zinc-900 dark:hover:bg-zinc-300"
        >
          Start Exploring
        </button>
      </div>
    </div>
  );
}
