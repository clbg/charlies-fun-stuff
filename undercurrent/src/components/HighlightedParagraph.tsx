"use client";

import { useEffect, useRef } from "react";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";

interface HighlightedParagraphProps {
  markdown: string;
  /** Texts to highlight (selectedText from children anchored to this paragraph) */
  highlights: string[];
  paragraphIndex: number;
  isStreaming?: boolean;
  isLastBlock?: boolean;
}

/**
 * Renders a markdown block with highlighted spans for selected text
 * that spawned child explorations.
 */
export function HighlightedParagraph({
  markdown,
  highlights,
  paragraphIndex,
  isStreaming,
  isLastBlock,
}: HighlightedParagraphProps) {
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!ref.current || highlights.length === 0) return;

    // Clear previous highlights
    ref.current.querySelectorAll("mark[data-uc-highlight]").forEach((mark) => {
      const parent = mark.parentNode;
      if (parent) {
        parent.replaceChild(document.createTextNode(mark.textContent || ""), mark);
        parent.normalize();
      }
    });

    // Apply new highlights
    for (const text of highlights) {
      highlightText(ref.current, text);
    }
  }, [highlights]);

  return (
    <div
      ref={ref}
      data-paragraph-index={paragraphIndex}
      className="prose prose-zinc max-w-none dark:prose-invert prose-p:my-2 prose-headings:my-3 prose-ul:my-2 prose-ol:my-2 prose-pre:my-2"
    >
      <ReactMarkdown remarkPlugins={[remarkGfm]}>{markdown}</ReactMarkdown>
      {isStreaming && isLastBlock && (
        <span className="inline-block w-2 h-4 bg-zinc-400 dark:bg-zinc-500 animate-pulse ml-0.5 align-text-bottom" />
      )}
    </div>
  );
}

/**
 * Walk the DOM tree and wrap the first occurrence of `text` in a <mark>.
 */
function highlightText(root: HTMLElement, text: string) {
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
  const needle = text.toLowerCase();

  while (walker.nextNode()) {
    const node = walker.currentNode as Text;
    const content = node.textContent || "";
    const idx = content.toLowerCase().indexOf(needle);
    if (idx === -1) continue;

    const before = content.slice(0, idx);
    const match = content.slice(idx, idx + text.length);
    const after = content.slice(idx + text.length);

    const mark = document.createElement("mark");
    mark.setAttribute("data-uc-highlight", "");
    mark.className =
      "bg-amber-100 dark:bg-amber-900/40 text-inherit rounded-sm px-0.5 -mx-0.5";
    mark.textContent = match;

    const parent = node.parentNode!;
    if (before) parent.insertBefore(document.createTextNode(before), node);
    parent.insertBefore(mark, node);
    if (after) parent.insertBefore(document.createTextNode(after), node);
    parent.removeChild(node);

    return; // Only highlight first occurrence
  }
}
