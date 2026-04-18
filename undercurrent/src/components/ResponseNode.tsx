"use client";

import { useMemo, useState, useCallback } from "react";
import type { TreeNode } from "@/lib/types";
import { CollapsibleBlock } from "./CollapsibleBlock";
import { StatusIndicator } from "./StatusIndicator";
import { HighlightedParagraph } from "./HighlightedParagraph";

interface ResponseNodeProps {
  node: TreeNode;
  collapsedIds: Set<string>;
  onToggleCollapse: (nodeId: string) => void;
  onDeleteNode: (nodeId: string) => void;
  onIronNode: (nodeId: string) => void;
  onIronUpNode: (nodeId: string) => void;
  onEditNode: (nodeId: string, newMarkdown: string) => void;
  ironingNodeId: string | null;
  depth?: number;
}

export function ResponseNode({
  node,
  collapsedIds,
  onToggleCollapse,
  onDeleteNode,
  onIronNode,
  onIronUpNode,
  onEditNode,
  ironingNodeId,
  depth = 0,
}: ResponseNodeProps) {
  const [editingId, setEditingId] = useState<string | null>(null);
  const [editText, setEditText] = useState("");

  const paragraphs = splitMarkdownBlocks(node.responseMarkdown);
  const isWaiting = node.status === "spawning" || node.status === "thinking";
  const hasContent = node.responseMarkdown.length > 0;
  const isAnnotation = !!node.isAnnotation;

  const highlightsByParagraph = useMemo(() => {
    const map: Record<number, string[]> = {};
    for (const child of node.children) {
      const idx = child.anchorParagraphIndex;
      if (!map[idx]) map[idx] = [];
      map[idx].push(child.selectedText);
    }
    return map;
  }, [node.children]);

  const startEditing = useCallback(
    (nodeId: string, markdown: string) => {
      setEditingId(nodeId);
      setEditText(markdown);
    },
    []
  );

  const commitEdit = useCallback(() => {
    if (editingId && editText !== node.responseMarkdown) {
      onEditNode(editingId, editText);
    }
    setEditingId(null);
  }, [editingId, editText, node.responseMarkdown, onEditNode]);

  const isEditing = editingId === node.id;

  return (
    <div data-node-id={node.id} className="relative">
      {isWaiting && <StatusIndicator node={node} />}

      {node.status === "error" && (
        <div className="rounded-lg border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700 dark:border-red-800 dark:bg-red-950 dark:text-red-300">
          {node.error || "Something went wrong"}
        </div>
      )}

      {isEditing ? (
        <div className={`rounded-lg p-3 ${isAnnotation ? "bg-amber-50 dark:bg-amber-950/30" : ""}`}>
          <textarea
            value={editText}
            onChange={(e) => setEditText(e.target.value)}
            className="w-full min-h-[120px] rounded-lg border border-zinc-300 bg-white p-3 text-sm font-mono outline-none dark:border-zinc-600 dark:bg-zinc-900 dark:text-zinc-100"
            onKeyDown={(e) => {
              if (e.key === "Escape") setEditingId(null);
              if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) commitEdit();
            }}
            autoFocus
          />
          <div className="mt-2 flex gap-2 justify-end">
            <button
              onClick={() => setEditingId(null)}
              className="rounded-md px-3 py-1 text-xs text-zinc-500 hover:text-zinc-700"
            >
              Cancel
            </button>
            <button
              onClick={commitEdit}
              className="rounded-md bg-zinc-900 px-3 py-1 text-xs font-medium text-white hover:bg-zinc-700 dark:bg-zinc-100 dark:text-zinc-900"
            >
              Save (⌘↩)
            </button>
          </div>
        </div>
      ) : (
        <>
          {hasContent && (
            <div
              className={`group/content relative ${isAnnotation ? "rounded-lg bg-amber-50/50 px-3 py-2 dark:bg-amber-950/20" : ""}`}
              onDoubleClick={() => {
                if (node.status === "done") startEditing(node.id, node.responseMarkdown);
              }}
            >
              {node.status === "done" && (
                <button
                  onClick={() => startEditing(node.id, node.responseMarkdown)}
                  className="absolute top-1 right-1 w-6 h-6 p-1 rounded text-zinc-300 hover:text-zinc-500 dark:text-zinc-600 dark:hover:text-zinc-400 opacity-0 group-hover/content:opacity-100 transition-all"
                >
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                    <path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7" />
                    <path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z" />
                  </svg>
                </button>
              )}
              {paragraphs.map((block, i) => {
                const childrenHere = node.children.filter(
                  (c) => c.anchorParagraphIndex === i
                );
                const isLastBlock = i === paragraphs.length - 1;

                return (
                  <div key={i}>
                    <HighlightedParagraph
                      markdown={block}
                      highlights={highlightsByParagraph[i] || []}
                      paragraphIndex={i}
                      isStreaming={node.status === "streaming"}
                      isLastBlock={isLastBlock}
                    />

                    {childrenHere.map((child) => (
                      <CollapsibleBlock
                        key={child.id}
                        node={child}
                        isCollapsed={collapsedIds.has(child.id)}
                        onToggle={() => onToggleCollapse(child.id)}
                        onDelete={() => onDeleteNode(child.id)}
                        onIron={() => onIronNode(child.id)}
                        onIronUp={() => onIronUpNode(child.id)}
                        isIroning={ironingNodeId === child.id}
                        depth={depth + 1}
                      >
                        <ResponseNode
                          node={child}
                          collapsedIds={collapsedIds}
                          onToggleCollapse={onToggleCollapse}
                          onDeleteNode={onDeleteNode}
                          onIronNode={onIronNode}
                          onIronUpNode={onIronUpNode}
                          onEditNode={onEditNode}
                          ironingNodeId={ironingNodeId}
                          depth={depth + 1}
                        />
                      </CollapsibleBlock>
                    ))}
                  </div>
                );
              })}
            </div>
          )}
        </>
      )}
    </div>
  );
}

function splitMarkdownBlocks(md: string): string[] {
  if (!md) return [];

  const blocks: string[] = [];
  const lines = md.split("\n");
  let current: string[] = [];
  let inCodeFence = false;

  for (const line of lines) {
    if (line.startsWith("```")) {
      inCodeFence = !inCodeFence;
    }

    if (!inCodeFence && line === "" && current.length > 0) {
      const block = current.join("\n").trim();
      if (block) blocks.push(block);
      current = [];
    } else {
      current.push(line);
    }
  }

  if (current.length > 0) {
    const block = current.join("\n").trim();
    if (block) blocks.push(block);
  }

  return blocks;
}
