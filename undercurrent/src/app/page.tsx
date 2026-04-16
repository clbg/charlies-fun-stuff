"use client";

import { useState, useCallback } from "react";
import type { Engine } from "@/lib/types";
import { InputBar } from "@/components/InputBar";
import { ResponseNode } from "@/components/ResponseNode";
import { SelectionToolbar } from "@/components/SelectionToolbar";
import { Toolbar } from "@/components/Toolbar";
import { SessionPicker } from "@/components/SessionPicker";
import { WelcomeScreen } from "@/components/WelcomeScreen";
import { useExploreTree } from "@/hooks/useExploreTree";
import { useSelection } from "@/hooks/useSelection";

export default function Home() {
  const [engine, setEngine] = useState<Engine | null>(null);
  const tree = useExploreTree();
  const { selection, clearSelection } = useSelection();

  const handleGoDeeper = (
    nodeId: string,
    paragraphIndex: number,
    text: string
  ) => {
    tree.addChild(nodeId, paragraphIndex, text);
  };

  const handleAskAbout = (
    nodeId: string,
    paragraphIndex: number,
    text: string,
    question: string
  ) => {
    tree.addChild(nodeId, paragraphIndex, text, question);
  };

  /** Iron result → new session with the flattened text as root */
  const handleFlattenResult = useCallback(
    (markdown: string) => {
      const label = "Ironed: " + (tree.rootInput?.slice(0, 30) || "doc");
      tree.newSessionFrom(label, markdown);
    },
    [tree]
  );

  // ── Welcome screen ─────────────────────────────────
  if (!engine) {
    return <WelcomeScreen onStart={setEngine} />;
  }

  // ── Main UI ────────────────────────────────────────
  return (
    <div className="flex flex-1 flex-col bg-zinc-50 pt-8 font-sans dark:bg-zinc-950">
      {/* Header */}
      <header className="border-b border-zinc-200 bg-white px-6 py-4 pl-20 dark:border-zinc-800 dark:bg-zinc-900">
        <div className="mx-auto flex max-w-3xl items-center justify-between">
          <div className="flex items-center gap-3">
            <h1 className="text-lg font-semibold text-zinc-900 dark:text-zinc-100">
              Undercurrent
            </h1>
            <SessionPicker
              sessions={tree.sessions}
              currentId={tree.currentSessionId}
              onSwitch={tree.switchSession}
              onNew={tree.newSession}
            />
            <button
              onClick={() => setEngine(null)}
              className="rounded-md bg-zinc-100 px-2 py-0.5 text-xs text-zinc-500 transition-colors hover:bg-zinc-200 hover:text-zinc-800 dark:bg-zinc-800 dark:text-zinc-400 dark:hover:bg-zinc-700"
              title="Switch engine"
            >
              {engine}
            </button>
          </div>
          <Toolbar
            rootInput={tree.rootInput}
            rootNode={tree.rootNode}
            onCollapseAll={tree.collapseAll}
            onFlattenResult={handleFlattenResult}
          />
        </div>
      </header>

      {/* Main content */}
      <main className="flex-1 overflow-y-auto px-6 py-8">
        <div className="mx-auto max-w-3xl">
          <InputBar
            onSubmit={tree.submitRoot}
            disabled={tree.rootNode?.status === "spawning"}
          />

          {tree.rootNode && (
            <div className="mt-8">
              <div className="mb-4 rounded-lg bg-white px-4 py-3 text-sm text-zinc-600 shadow-sm dark:bg-zinc-900 dark:text-zinc-400">
                {tree.rootInput}
              </div>
              <div className="rounded-xl bg-white p-6 shadow-sm dark:bg-zinc-900">
                <ResponseNode
                  node={tree.rootNode}
                  collapsedIds={tree.collapsedIds}
                  onToggleCollapse={tree.toggleCollapse}
                />
              </div>
            </div>
          )}

          {!tree.rootNode && (
            <div className="mt-32 text-center text-zinc-400 dark:text-zinc-600">
              <p className="text-4xl mb-4">〰</p>
              <p className="text-sm">What&apos;s beneath the surface?</p>
            </div>
          )}
        </div>
      </main>

      <SelectionToolbar
        selection={selection}
        onGoDeeper={handleGoDeeper}
        onAskAbout={handleAskAbout}
        onDismiss={clearSelection}
      />
    </div>
  );
}
