"use client";

import { useCallback, useState } from "react";
import type { TreeNode } from "@/lib/types";
import {
  exportAsMarkdown,
  exportAsHTML,
  collectTreeContent,
} from "@/lib/export";

interface ToolbarProps {
  rootInput: string | null;
  rootNode: TreeNode | null;
  onCollapseAll: () => void;
  onFlattenResult: (markdown: string) => void;
}

export function Toolbar({
  rootInput,
  rootNode,
  onCollapseAll,
  onFlattenResult,
}: ToolbarProps) {
  const [flattenStatus, setFlattenStatus] = useState<
    "idle" | "loading" | "done"
  >("idle");

  const hasTree = rootNode && rootInput;

  const handleExportMarkdown = useCallback(() => {
    if (!hasTree) return;
    const md = exportAsMarkdown(rootInput, rootNode);
    navigator.clipboard.writeText(md);
    alert("Markdown copied to clipboard!");
  }, [rootInput, rootNode, hasTree]);

  const handleExportHTML = useCallback(() => {
    if (!hasTree) return;
    const html = exportAsHTML(rootInput, rootNode);
    const blob = new Blob([html], { type: "text/html" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = "undercurrent-export.html";
    a.click();
    URL.revokeObjectURL(url);
  }, [rootInput, rootNode, hasTree]);

  const handleFlatten = useCallback(async () => {
    if (!hasTree) return;
    if (rootNode.children.length === 0) {
      alert("No branches to flatten. Explore some concepts first!");
      return;
    }

    setFlattenStatus("loading");
    const treeContent = collectTreeContent(rootInput, rootNode);
    const nodeId = `flatten-${Date.now()}`;

    try {
      const res = await fetch("/api/flatten", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ treeContent, nodeId }),
      });

      const reader = res.body?.getReader();
      if (!reader) throw new Error("No response body");

      const decoder = new TextDecoder();
      let buffer = "";
      let result = "";

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;

        buffer += decoder.decode(value, { stream: true });
        const lines = buffer.split("\n\n");
        buffer = lines.pop() || "";

        for (const line of lines) {
          if (!line.startsWith("data: ")) continue;
          const json = JSON.parse(line.slice(6));
          if (json.type === "chunk") result += json.text;
        }
      }

      onFlattenResult(result);
      setFlattenStatus("done");
    } catch {
      setFlattenStatus("idle");
      alert("Flatten failed. Try again.");
    }
  }, [rootInput, rootNode, hasTree, onFlattenResult]);

  if (!hasTree) return null;

  return (
    <div className="flex items-center gap-2">
      <button
        onClick={onCollapseAll}
        className="text-sm text-zinc-500 hover:text-zinc-800 dark:text-zinc-400 dark:hover:text-zinc-200 transition-colors"
      >
        Collapse all
      </button>
      <span className="text-zinc-300 dark:text-zinc-700">|</span>
      <button
        onClick={handleExportMarkdown}
        className="text-sm text-zinc-500 hover:text-zinc-800 dark:text-zinc-400 dark:hover:text-zinc-200 transition-colors"
      >
        Copy MD
      </button>
      <button
        onClick={handleExportHTML}
        className="text-sm text-zinc-500 hover:text-zinc-800 dark:text-zinc-400 dark:hover:text-zinc-200 transition-colors"
      >
        Export HTML
      </button>
      <button
        onClick={handleFlatten}
        disabled={flattenStatus === "loading"}
        className="text-sm text-zinc-500 hover:text-zinc-800 dark:text-zinc-400 dark:hover:text-zinc-200 transition-colors disabled:opacity-50"
      >
        {flattenStatus === "loading" ? "Ironing..." : "Iron ✨"}
      </button>
    </div>
  );
}
