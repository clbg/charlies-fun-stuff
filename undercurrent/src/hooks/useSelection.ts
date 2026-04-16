"use client";

import { useCallback, useEffect, useState } from "react";

export interface SelectionInfo {
  text: string;
  rect: DOMRect;
  /** The data-node-id of the ResponseNode containing the selection */
  nodeId: string;
  /** The index of the paragraph (data-paragraph-index) closest to selection start */
  paragraphIndex: number;
}

export function useSelection() {
  const [selection, setSelection] = useState<SelectionInfo | null>(null);

  const handleMouseUp = useCallback((e: MouseEvent) => {
    // Don't clear selection if mouseup is on the toolbar
    const target = e.target as Element;
    if (target.closest?.("[data-selection-toolbar]")) return;

    // Small delay to let browser finalize selection
    requestAnimationFrame(() => {
      const sel = window.getSelection();
      if (!sel || sel.isCollapsed || !sel.toString().trim()) {
        setSelection(null);
        return;
      }

      const range = sel.getRangeAt(0);
      const rect = range.getBoundingClientRect();
      const text = sel.toString().trim();

      // Find the closest ResponseNode ancestor
      const startContainer =
        range.startContainer instanceof Element
          ? range.startContainer
          : range.startContainer.parentElement;

      const responseNode = startContainer?.closest("[data-node-id]");
      const nodeId = responseNode?.getAttribute("data-node-id");

      // Find the closest paragraph
      const paragraph = startContainer?.closest("[data-paragraph-index]");
      const paragraphIndex = parseInt(
        paragraph?.getAttribute("data-paragraph-index") || "0",
        10
      );

      if (!nodeId) {
        setSelection(null);
        return;
      }

      setSelection({ text, rect, nodeId, paragraphIndex });
    });
  }, []);

  const clearSelection = useCallback(() => {
    setSelection(null);
    window.getSelection()?.removeAllRanges();
  }, []);

  useEffect(() => {
    document.addEventListener("mouseup", handleMouseUp);
    return () => document.removeEventListener("mouseup", handleMouseUp);
  }, [handleMouseUp]);

  return { selection, clearSelection };
}
