"use client";

import { useState } from "react";
import type { TreeNode } from "@/lib/types";

interface IronPanelProps {
  mode: "up" | "down";
  childNodes: TreeNode[];
  onSubmit: (instruction: string, excludeNodeIds: string[]) => void;
  onCancel: () => void;
}

export function IronPanel({
  mode,
  childNodes,
  onSubmit,
  onCancel,
}: IronPanelProps) {
  const [instruction, setInstruction] = useState("");
  const [excludeIds, setExcludeIds] = useState<Set<string>>(new Set());

  const toggleChild = (id: string) => {
    setExcludeIds((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  const handleSubmit = () => onSubmit(instruction, [...excludeIds]);

  return (
    <div className="mt-2 mb-2 rounded-lg border border-zinc-200 bg-zinc-50 p-3 dark:border-zinc-700 dark:bg-zinc-800/50">
      <input
        value={instruction}
        onChange={(e) => setInstruction(e.target.value)}
        placeholder="Style instructions (e.g. 'keep it concise', 'academic tone')..."
        className="w-full rounded-md border border-zinc-300 bg-white px-3 py-1.5 text-sm outline-none placeholder:text-zinc-400 dark:border-zinc-600 dark:bg-zinc-900 dark:text-zinc-100"
        onKeyDown={(e) => {
          if (e.key === "Enter") handleSubmit();
          if (e.key === "Escape") onCancel();
        }}
        autoFocus
      />
      {mode === "down" && childNodes.length > 1 && (
        <div className="mt-2 space-y-1">
          <div className="text-xs text-zinc-400 mb-1">Include branches:</div>
          {childNodes.map((child) => (
            <label
              key={child.id}
              className="flex items-center gap-2 text-sm text-zinc-600 dark:text-zinc-300 cursor-pointer"
            >
              <input
                type="checkbox"
                checked={!excludeIds.has(child.id)}
                onChange={() => toggleChild(child.id)}
                className="rounded"
              />
              <span className="truncate">
                {child.isAnnotation && "📝 "}
                {child.userQuestion ||
                  `"${child.selectedText.slice(0, 60)}${child.selectedText.length > 60 ? "..." : ""}"`}
              </span>
            </label>
          ))}
        </div>
      )}
      <div className="mt-2 flex gap-2 justify-end">
        <button
          onClick={onCancel}
          className="rounded-md px-3 py-1 text-xs text-zinc-500 hover:text-zinc-700 dark:text-zinc-400 dark:hover:text-zinc-200"
        >
          Cancel
        </button>
        <button
          onClick={handleSubmit}
          className="rounded-md bg-zinc-900 px-3 py-1 text-xs font-medium text-white hover:bg-zinc-700 dark:bg-zinc-100 dark:text-zinc-900 dark:hover:bg-zinc-300"
        >
          Iron {mode === "up" ? "↑" : "↓"}
        </button>
      </div>
    </div>
  );
}
