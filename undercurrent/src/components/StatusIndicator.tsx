"use client";

import { useEffect, useState } from "react";
import type { TreeNode } from "@/lib/types";

interface StatusIndicatorProps {
  node: TreeNode;
}

const statusMessages = {
  spawning: "Connecting to Claude CLI...",
  thinking: "Claude is thinking...",
  streaming: "", // not shown — text is visible
  done: "",
  error: "",
};

export function StatusIndicator({ node }: StatusIndicatorProps) {
  const [elapsed, setElapsed] = useState(0);

  useEffect(() => {
    if (!node.startedAt) return;
    if (node.status === "done" || node.status === "error") return;

    const interval = setInterval(() => {
      setElapsed(Math.floor((Date.now() - node.startedAt!) / 1000));
    }, 1000);

    return () => clearInterval(interval);
  }, [node.startedAt, node.status]);

  const message = statusMessages[node.status];
  if (!message) return null;

  return (
    <div className="flex items-center gap-3 py-3 text-sm text-zinc-400">
      <span className="inline-block h-4 w-4 animate-spin rounded-full border-2 border-zinc-300 border-t-zinc-600 dark:border-zinc-600 dark:border-t-zinc-300" />
      <span>{message}</span>
      {elapsed > 0 && (
        <span className="text-zinc-300 dark:text-zinc-600">{elapsed}s</span>
      )}
    </div>
  );
}
