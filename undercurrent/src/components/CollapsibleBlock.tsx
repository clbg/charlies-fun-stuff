"use client";

import { useState } from "react";
import type { TreeNode } from "@/lib/types";
import type { ReactNode } from "react";
import { IronPanel } from "./IronPanel";

interface CollapsibleBlockProps {
  node: TreeNode;
  isCollapsed: boolean;
  onToggle: () => void;
  onDelete: () => void;
  onIron: (instruction: string, excludeNodeIds: string[]) => void;
  onIronUp: (instruction: string, excludeNodeIds: string[]) => void;
  isIroning: boolean;
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
  onDelete,
  onIron,
  onIronUp,
  isIroning,
  depth,
  children,
}: CollapsibleBlockProps) {
  const [ironPanelMode, setIronPanelMode] = useState<"up" | "down" | null>(null);

  const isAnnotation = !!node.isAnnotation;
  const borderColor = isAnnotation
    ? "border-amber-400"
    : depthColors[depth % depthColors.length];
  const hasChildren = node.children.length > 0;
  const isDone = node.status === "done";
  const allChildrenDone =
    hasChildren &&
    node.children.every(
      (c) => c.status === "done" || c.status === "error"
    );

  return (
    <div className={`ml-4 my-2 border-l-2 ${borderColor} pl-4`}>
      {/* Header */}
      <div className="flex items-center gap-2 group">
        <button
          onClick={onToggle}
          className={`flex items-center gap-2 text-sm transition-colors flex-1 min-w-0 text-left py-1 ${
            isAnnotation
              ? "text-amber-600 hover:text-amber-800 dark:text-amber-400 dark:hover:text-amber-200"
              : "text-zinc-500 hover:text-zinc-800 dark:text-zinc-400 dark:hover:text-zinc-200"
          }`}
        >
          <span
            className={`inline-block transition-transform flex-shrink-0 ${isCollapsed ? "" : "rotate-90"}`}
          >
            ▶
          </span>
          <span className="truncate font-medium">
            {isAnnotation ? (
              <>
                <span className="text-amber-400">📝 </span>
                on &ldquo;{node.selectedText.slice(0, 60)}
                {node.selectedText.length > 60 ? "..." : ""}&rdquo;
              </>
            ) : node.userQuestion ? (
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
          {(node.status === "spawning" ||
            node.status === "thinking" ||
            node.status === "streaming") && (
            <span className="inline-block h-3 w-3 animate-spin rounded-full border border-zinc-300 border-t-zinc-600 flex-shrink-0" />
          )}
        </button>

        {/* Action buttons — visible on hover */}
        <div className="flex items-center gap-0.5 flex-shrink-0 opacity-40 group-hover:opacity-100 transition-opacity">
          {isDone && !isIroning && (
            <button
              onClick={() => setIronPanelMode(ironPanelMode === "up" ? null : "up")}
              className="rounded px-1.5 py-0.5 text-xs text-zinc-400 hover:text-zinc-700 hover:bg-zinc-100 dark:hover:text-zinc-200 dark:hover:bg-zinc-800 transition-colors"
              title="Merge this branch into parent"
            >
              Iron ↑
            </button>
          )}
          {allChildrenDone && isDone && !isIroning && (
            <button
              onClick={() => setIronPanelMode(ironPanelMode === "down" ? null : "down")}
              className="rounded px-1.5 py-0.5 text-xs text-zinc-400 hover:text-zinc-700 hover:bg-zinc-100 dark:hover:text-zinc-200 dark:hover:bg-zinc-800 transition-colors"
              title="Merge children into this node"
            >
              Iron ↓
            </button>
          )}
          {isIroning && (
            <span className="flex items-center gap-1 text-xs text-zinc-400">
              <span className="inline-block h-2.5 w-2.5 animate-spin rounded-full border border-zinc-300 border-t-zinc-600" />
              Ironing
            </span>
          )}
          <button
            onClick={onDelete}
            className="rounded px-1.5 py-0.5 text-xs text-zinc-400 hover:text-red-600 hover:bg-red-50 dark:hover:text-red-400 dark:hover:bg-red-950 transition-colors"
          >
            ✕
          </button>
        </div>
      </div>

      {/* Iron Panel */}
      {ironPanelMode && (
        <IronPanel
          mode={ironPanelMode}
          childNodes={node.children}
          onSubmit={(instruction, excludeIds) => {
            if (ironPanelMode === "up") {
              onIronUp(instruction, excludeIds);
            } else {
              onIron(instruction, excludeIds);
            }
            setIronPanelMode(null);
          }}
          onCancel={() => setIronPanelMode(null)}
        />
      )}

      {/* Content */}
      {!isCollapsed && <div className="mt-1">{children}</div>}
    </div>
  );
}
