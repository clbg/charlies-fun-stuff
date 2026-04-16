"use client";

import { useEffect, useRef, useState, type FormEvent } from "react";
import type { SelectionInfo } from "@/hooks/useSelection";

interface SelectionToolbarProps {
  selection: SelectionInfo | null;
  onGoDeeper: (nodeId: string, paragraphIndex: number, text: string) => void;
  onAskAbout: (
    nodeId: string,
    paragraphIndex: number,
    text: string,
    question: string
  ) => void;
  onDismiss: () => void;
}

export function SelectionToolbar({
  selection,
  onGoDeeper,
  onAskAbout,
  onDismiss,
}: SelectionToolbarProps) {
  const [askMode, setAskMode] = useState(false);
  const [question, setQuestion] = useState("");
  const toolbarRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  // Reset ask mode when selection changes
  useEffect(() => {
    setAskMode(false);
    setQuestion("");
  }, [selection?.text]);

  // Focus input when ask mode opens
  useEffect(() => {
    if (askMode) inputRef.current?.focus();
  }, [askMode]);

  // Dismiss on click outside
  useEffect(() => {
    const handleMouseDown = (e: MouseEvent) => {
      if (
        toolbarRef.current &&
        !toolbarRef.current.contains(e.target as Node)
      ) {
        onDismiss();
      }
    };
    document.addEventListener("mousedown", handleMouseDown);
    return () => document.removeEventListener("mousedown", handleMouseDown);
  }, [onDismiss]);

  if (!selection) return null;

  const { rect, nodeId, paragraphIndex, text } = selection;

  const style: React.CSSProperties = {
    position: "fixed",
    top: rect.top - 8,
    left: rect.left + rect.width / 2,
    transform: "translate(-50%, -100%)",
    zIndex: 50,
  };

  const handleGoDeeper = () => {
    onGoDeeper(nodeId, paragraphIndex, text);
    onDismiss();
  };

  const handleAskSubmit = (e: FormEvent) => {
    e.preventDefault();
    if (!question.trim()) return;
    onAskAbout(nodeId, paragraphIndex, text, question.trim());
    onDismiss();
  };

  return (
    <div ref={toolbarRef} style={style} data-selection-toolbar>
      <div className="rounded-xl border border-zinc-200 bg-white px-1 py-1 shadow-lg dark:border-zinc-700 dark:bg-zinc-800">
        {!askMode ? (
          <div className="flex items-center gap-1">
            <button
              onClick={handleGoDeeper}
              className="rounded-lg px-3 py-1.5 text-sm font-medium text-zinc-700 transition-colors hover:bg-zinc-100 dark:text-zinc-300 dark:hover:bg-zinc-700"
            >
              Go deeper
            </button>
            <div className="h-4 w-px bg-zinc-200 dark:bg-zinc-700" />
            <button
              onClick={() => setAskMode(true)}
              className="rounded-lg px-3 py-1.5 text-sm font-medium text-zinc-700 transition-colors hover:bg-zinc-100 dark:text-zinc-300 dark:hover:bg-zinc-700"
            >
              Ask about this
            </button>
          </div>
        ) : (
          <form onSubmit={handleAskSubmit} className="flex items-center gap-1">
            <input
              ref={inputRef}
              value={question}
              onChange={(e) => setQuestion(e.target.value)}
              placeholder="Your question..."
              className="w-64 rounded-lg border-0 bg-transparent px-3 py-1.5 text-sm text-zinc-900 outline-none placeholder:text-zinc-400 dark:text-zinc-100"
              onKeyDown={(e) => {
                if (e.key === "Escape") {
                  setAskMode(false);
                  setQuestion("");
                }
              }}
            />
            <button
              type="submit"
              disabled={!question.trim()}
              className="rounded-lg bg-zinc-900 px-3 py-1.5 text-sm font-medium text-white transition-colors hover:bg-zinc-700 disabled:opacity-30 dark:bg-zinc-100 dark:text-zinc-900"
            >
              Ask
            </button>
          </form>
        )}
      </div>
    </div>
  );
}
