"use client";

import type { TreeNode } from "@/lib/types";
import type { ReactNode } from "react";

interface CollapsibleBlockProps {
  node: TreeNode;
  isCollapsed: boolean;
  onToggle: () => void;
  depth: number;
  children: ReactNode;
}

const depthColors = [
  "border-blue-400",
  "border-emerald-400",
  "border-amber-400",
  "border-purple-400",
  "border-rose-400",
  "border-cyan-400",
  "border-orange-400",
  "border-pink-400",
];

export function CollapsibleBlock({
  node,
  isCollapsed,
  onToggle,
  depth,
  children,
}: CollapsibleBlockProps) {
  const borderColor = depthColors[depth % depthColors.length];

  return (
    <div className={`ml-4 my-2 border-l-2 ${borderColor} pl-4`}>
      {/* Header */}
      <button
        onClick={onToggle}
        className="flex items-center gap-2 text-sm text-zinc-500 hover:text-zinc-800 dark:text-zinc-400 dark:hover:text-zinc-200 transition-colors group w-full text-left py-1"
      >
        <span
          className={`inline-block transition-transform ${isCollapsed ? "" : "rotate-90"}`}
        >
          ▶
        </span>
        <span className="truncate font-medium">
          {node.userQuestion ? (
            <>
              <span className="text-zinc-400">Q: </span>
              {node.userQuestion}
            </>
          ) : (
            <>
              <span className="text-zinc-400">↳ </span>
              &ldquo;{node.selectedText.slice(0, 80)}
              {node.selectedText.length > 80 ? "..." : ""}&rdquo;
            </>
          )}
        </span>
        {node.status === "spawning" || node.status === "thinking" || node.status === "streaming" ? (
          <span className="inline-block h-3 w-3 animate-spin rounded-full border border-zinc-300 border-t-zinc-600 flex-shrink-0" />
        ) : null}
      </button>

      {/* Content */}
      {!isCollapsed && <div className="mt-1">{children}</div>}
    </div>
  );
}
