"use client";

import { useState, useRef, useEffect } from "react";
import type { Session } from "@/hooks/useExploreTree";

interface SessionPickerProps {
  sessions: Session[];
  currentId: string;
  onSwitch: (id: string) => void;
  onNew: () => void;
}

export function SessionPicker({
  sessions,
  currentId,
  onSwitch,
  onNew,
}: SessionPickerProps) {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    const handler = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) {
        setOpen(false);
      }
    };
    document.addEventListener("mousedown", handler);
    return () => document.removeEventListener("mousedown", handler);
  }, [open]);

  const current = sessions.find((s) => s.id === currentId);

  return (
    <div className="relative" ref={ref}>
      <button
        onClick={() => setOpen(!open)}
        className="flex items-center gap-1.5 rounded-md bg-zinc-100 px-2.5 py-1 text-xs text-zinc-600 transition-colors hover:bg-zinc-200 dark:bg-zinc-800 dark:text-zinc-400 dark:hover:bg-zinc-700"
      >
        <span className="max-w-[120px] truncate">
          {current?.label || "New"}
        </span>
        <svg
          className={`h-3 w-3 transition-transform ${open ? "rotate-180" : ""}`}
          fill="none"
          viewBox="0 0 24 24"
          stroke="currentColor"
          strokeWidth={2}
        >
          <path strokeLinecap="round" strokeLinejoin="round" d="M19 9l-7 7-7-7" />
        </svg>
      </button>

      {open && (
        <div className="absolute left-0 top-full z-50 mt-1 w-56 rounded-xl border border-zinc-200 bg-white py-1 shadow-lg dark:border-zinc-700 dark:bg-zinc-900">
          {sessions.map((s) => (
            <button
              key={s.id}
              onClick={() => {
                onSwitch(s.id);
                setOpen(false);
              }}
              className={`flex w-full items-center gap-2 px-3 py-2 text-left text-sm transition-colors ${
                s.id === currentId
                  ? "bg-zinc-100 text-zinc-900 dark:bg-zinc-800 dark:text-zinc-100"
                  : "text-zinc-600 hover:bg-zinc-50 dark:text-zinc-400 dark:hover:bg-zinc-800"
              }`}
            >
              <span className="truncate">{s.label}</span>
              {s.rootNode && !s.rootNode.children.length && (
                <span className="ml-auto text-[10px] text-zinc-400">base</span>
              )}
              {s.rootNode && s.rootNode.children.length > 0 && (
                <span className="ml-auto text-[10px] text-zinc-400">
                  {s.rootNode.children.length} branches
                </span>
              )}
            </button>
          ))}
          <div className="border-t border-zinc-200 dark:border-zinc-700" />
          <button
            onClick={() => {
              onNew();
              setOpen(false);
            }}
            className="flex w-full items-center gap-2 px-3 py-2 text-left text-sm text-zinc-500 transition-colors hover:bg-zinc-50 dark:hover:bg-zinc-800"
          >
            + New session
          </button>
        </div>
      )}
    </div>
  );
}
