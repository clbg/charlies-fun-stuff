"use client";

import { useMemo } from "react";
import type { TreeNode } from "@/lib/types";
import { CollapsibleBlock } from "./CollapsibleBlock";
import { StatusIndicator } from "./StatusIndicator";
import { HighlightedParagraph } from "./HighlightedParagraph";

interface ResponseNodeProps {
  node: TreeNode;
  collapsedIds: Set<string>;
  onToggleCollapse: (nodeId: string) => void;
  depth?: number;
}

export function ResponseNode({
  node,
  collapsedIds,
  onToggleCollapse,
  depth = 0,
}: ResponseNodeProps) {
  const paragraphs = splitMarkdownBlocks(node.responseMarkdown);
  const isWaiting = node.status === "spawning" || node.status === "thinking";
  const hasContent = node.responseMarkdown.length > 0;

  // Collect highlight texts per paragraph index
  const highlightsByParagraph = useMemo(() => {
    const map: Record<number, string[]> = {};
    for (const child of node.children) {
      const idx = child.anchorParagraphIndex;
      if (!map[idx]) map[idx] = [];
      map[idx].push(child.selectedText);
    }
    return map;
  }, [node.children]);

  return (
    <div data-node-id={node.id} className="relative">
      {/* Status indicator for spawning/thinking */}
      {isWaiting && <StatusIndicator node={node} />}

      {/* Error state */}
      {node.status === "error" && (
        <div className="rounded-lg border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700 dark:border-red-800 dark:bg-red-950 dark:text-red-300">
          {node.error || "Something went wrong"}
        </div>
      )}

      {/* Render paragraphs with child nodes interleaved */}
      {hasContent &&
        paragraphs.map((block, i) => {
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

              {/* Child expansions anchored to this paragraph */}
              {childrenHere.map((child) => (
                <CollapsibleBlock
                  key={child.id}
                  node={child}
                  isCollapsed={collapsedIds.has(child.id)}
                  onToggle={() => onToggleCollapse(child.id)}
                  depth={depth + 1}
                >
                  <ResponseNode
                    node={child}
                    collapsedIds={collapsedIds}
                    onToggleCollapse={onToggleCollapse}
                    depth={depth + 1}
                  />
                </CollapsibleBlock>
              ))}
            </div>
          );
        })}
    </div>
  );
}

/**
 * Split markdown into top-level blocks.
 * Preserves code fences as single blocks.
 */
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
