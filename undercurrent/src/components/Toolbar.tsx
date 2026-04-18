"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import type { TreeNode } from "@/lib/types";
import {
  exportAsMarkdown,
  exportAsHTML,
  collectTreeContent,
} from "@/lib/export";

interface ToolbarProps {
  rootInput: string | null;
  rootNode: TreeNode | null;
  collapsedIds: Set<string>;
  onCollapseAll: () => void;
  onFlattenResult: (markdown: string) => void;
  onImportSession: (json: string) => void;
}

export function Toolbar({
  rootInput,
  rootNode,
  collapsedIds,
  onCollapseAll,
  onFlattenResult,
  onImportSession,
}: ToolbarProps) {
  const [flattenStatus, setFlattenStatus] = useState<
    "idle" | "loading" | "done"
  >("idle");
  const [menuOpen, setMenuOpen] = useState(false);
  const menuRef = useRef<HTMLDivElement>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const hasTree = rootNode && rootInput;

  // Close menu on outside click (same pattern as SessionPicker)
  useEffect(() => {
    if (!menuOpen) return;
    const handler = (e: MouseEvent) => {
      if (menuRef.current && !menuRef.current.contains(e.target as Node)) {
        setMenuOpen(false);
      }
    };
    document.addEventListener("mousedown", handler);
    return () => document.removeEventListener("mousedown", handler);
  }, [menuOpen]);

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

  const handleExportJSON = useCallback(() => {
    if (!hasTree) return;
    const data = {
      label: rootInput.slice(0, 40),
      rootInput,
      rootNode,
      collapsedIds: [...collapsedIds],
    };
    const json = JSON.stringify(data, null, 2);
    const blob = new Blob([json], { type: "application/json" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = "undercurrent-session.json";
    a.click();
    URL.revokeObjectURL(url);
  }, [rootInput, rootNode, collapsedIds, hasTree]);

  const handleImport = useCallback(() => {
    fileInputRef.current?.click();
  }, []);

  const handleFileSelected = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      const file = e.target.files?.[0];
      if (!file) return;
      const reader = new FileReader();
      reader.onload = () => {
        if (typeof reader.result === "string") {
          onImportSession(reader.result);
        }
      };
      reader.readAsText(file);
      e.target.value = "";
    },
    [onImportSession]
  );

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

  return (
    <div className="flex items-center gap-2">
      <input
        ref={fileInputRef}
        type="file"
        accept=".json"
        className="hidden"
        onChange={handleFileSelected}
      />

      {/* Overflow menu */}
      <div className="relative" ref={menuRef}>
        <button
          onClick={() => setMenuOpen(!menuOpen)}
          className="flex h-7 w-7 items-center justify-center rounded-full text-sm text-zinc-400 transition-colors hover:bg-zinc-100 hover:text-zinc-600 dark:hover:bg-zinc-800 dark:hover:text-zinc-300"
          aria-label="More actions"
        >
          &middot;&middot;&middot;
        </button>

        {menuOpen && (
          <div className="absolute left-0 top-full z-50 mt-1 w-44 rounded-xl border border-zinc-200 bg-white py-1 shadow-lg dark:border-zinc-700 dark:bg-zinc-900">
            <button
              onClick={() => {
                handleImport();
                setMenuOpen(false);
              }}
              className="flex w-full px-3 py-2 text-left text-sm text-zinc-600 transition-colors hover:bg-zinc-50 dark:text-zinc-400 dark:hover:bg-zinc-800"
            >
              Import
            </button>
            {hasTree && (
              <>
                <button
                  onClick={() => {
                    handleExportMarkdown();
                    setMenuOpen(false);
                  }}
                  className="flex w-full px-3 py-2 text-left text-sm text-zinc-600 transition-colors hover:bg-zinc-50 dark:text-zinc-400 dark:hover:bg-zinc-800"
                >
                  Copy MD
                </button>
                <button
                  onClick={() => {
                    handleExportHTML();
                    setMenuOpen(false);
                  }}
                  className="flex w-full px-3 py-2 text-left text-sm text-zinc-600 transition-colors hover:bg-zinc-50 dark:text-zinc-400 dark:hover:bg-zinc-800"
                >
                  Export HTML
                </button>
                <button
                  onClick={() => {
                    handleExportJSON();
                    setMenuOpen(false);
                  }}
                  className="flex w-full px-3 py-2 text-left text-sm text-zinc-600 transition-colors hover:bg-zinc-50 dark:text-zinc-400 dark:hover:bg-zinc-800"
                >
                  Export JSON
                </button>
              </>
            )}
          </div>
        )}
      </div>

      {/* Primary actions */}
      {hasTree && (
        <>
          <button
            onClick={onCollapseAll}
            className="text-sm text-zinc-500 transition-colors hover:text-zinc-800 dark:text-zinc-400 dark:hover:text-zinc-200"
          >
            Collapse all
          </button>
          <button
            onClick={handleFlatten}
            disabled={flattenStatus === "loading"}
            className="rounded-lg bg-zinc-100 px-3 py-1 text-sm text-zinc-600 transition-colors hover:bg-zinc-200 disabled:opacity-50 dark:bg-zinc-800 dark:text-zinc-300 dark:hover:bg-zinc-700"
          >
            {flattenStatus === "loading" ? "Ironing..." : "Iron \u2728"}
          </button>
        </>
      )}
    </div>
  );
}
