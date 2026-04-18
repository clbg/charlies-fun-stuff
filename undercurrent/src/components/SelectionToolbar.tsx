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
  onAddNote: (
    nodeId: string,
    paragraphIndex: number,
    text: string,
    note: string
  ) => void;
  onDismiss: () => void;
}

type Mode = "actions" | "ask" | "note";

export function SelectionToolbar({
  selection,
  onGoDeeper,
  onAskAbout,
  onAddNote,
  onDismiss,
}: SelectionToolbarProps) {
  const [mode, setMode] = useState<Mode>("actions");
  const [input, setInput] = useState("");
  const toolbarRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);
  const textareaRef = useRef<HTMLTextAreaElement>(null);

  useEffect(() => {
    setMode("actions");
    setInput("");
  }, [selection?.text]);

  useEffect(() => {
    if (mode === "ask") inputRef.current?.focus();
    if (mode === "note") textareaRef.current?.focus();
  }, [mode]);

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
    if (!input.trim()) return;
    onAskAbout(nodeId, paragraphIndex, text, input.trim());
    onDismiss();
  };

  const handleNoteSubmit = (e: FormEvent) => {
    e.preventDefault();
    if (!input.trim()) return;
    onAddNote(nodeId, paragraphIndex, text, input.trim());
    onDismiss();
  };

  return (
    <div ref={toolbarRef} style={style} data-selection-toolbar>
      <div className="rounded-xl border border-zinc-200 bg-white px-1 py-1 shadow-lg dark:border-zinc-700 dark:bg-zinc-800">
        {mode === "actions" && (
          <div className="flex items-center gap-1">
            <button
              onClick={handleGoDeeper}
              className="rounded-lg px-3 py-1.5 text-sm font-medium text-zinc-700 transition-colors hover:bg-zinc-100 dark:text-zinc-300 dark:hover:bg-zinc-700"
            >
              Go deeper
            </button>
            <div className="h-4 w-px bg-zinc-200 dark:bg-zinc-700" />
            <button
              onClick={() => setMode("ask")}
              className="rounded-lg px-3 py-1.5 text-sm font-medium text-zinc-700 transition-colors hover:bg-zinc-100 dark:text-zinc-300 dark:hover:bg-zinc-700"
            >
              Ask about this
            </button>
            <div className="h-4 w-px bg-zinc-200 dark:bg-zinc-700" />
            <button
              onClick={() => setMode("note")}
              className="rounded-lg px-3 py-1.5 text-sm font-medium text-amber-600 transition-colors hover:bg-amber-50 dark:text-amber-400 dark:hover:bg-amber-950"
            >
              Add note
            </button>
          </div>
        )}
        {mode === "ask" && (
          <form onSubmit={handleAskSubmit} className="flex items-center gap-1">
            <input
              ref={inputRef}
              value={input}
              onChange={(e) => setInput(e.target.value)}
              placeholder="Your question..."
              className="w-64 rounded-lg border-0 bg-transparent px-3 py-1.5 text-sm text-zinc-900 outline-none placeholder:text-zinc-400 dark:text-zinc-100"
              onKeyDown={(e) => {
                if (e.key === "Escape") {
                  setMode("actions");
                  setInput("");
                }
              }}
            />
            <button
              type="submit"
              disabled={!input.trim()}
              className="rounded-lg bg-zinc-900 px-3 py-1.5 text-sm font-medium text-white transition-colors hover:bg-zinc-700 disabled:opacity-30 dark:bg-zinc-100 dark:text-zinc-900"
            >
              Ask
            </button>
          </form>
        )}
        {mode === "note" && (
          <form onSubmit={handleNoteSubmit} className="flex items-center gap-1">
            <textarea
              ref={textareaRef}
              value={input}
              onChange={(e) => setInput(e.target.value)}
              placeholder="Your thoughts..."
              rows={2}
              className="w-72 rounded-lg border-0 bg-transparent px-3 py-1.5 text-sm text-zinc-900 outline-none placeholder:text-zinc-400 dark:text-zinc-100 resize-none"
              onKeyDown={(e) => {
                if (e.key === "Escape") {
                  setMode("actions");
                  setInput("");
                }
                if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) {
                  e.preventDefault();
                  if (input.trim()) {
                    onAddNote(nodeId, paragraphIndex, text, input.trim());
                    onDismiss();
                  }
                }
              }}
            />
            <button
              type="submit"
              disabled={!input.trim()}
              className="rounded-lg bg-amber-500 px-3 py-1.5 text-sm font-medium text-white transition-colors hover:bg-amber-600 disabled:opacity-30"
            >
              Save
            </button>
          </form>
        )}
      </div>
    </div>
  );
}
