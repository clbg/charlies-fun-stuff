"use client";

import { useState, useCallback } from "react";
import type { Engine, TreeNode } from "@/lib/types";
import { collectSubtreeContent, collectIronUpContent } from "@/lib/export";
import { InputBar } from "@/components/InputBar";
import { ResponseNode } from "@/components/ResponseNode";
import { SelectionToolbar } from "@/components/SelectionToolbar";
import { Toolbar } from "@/components/Toolbar";
import { SessionPicker } from "@/components/SessionPicker";
import { WelcomeScreen } from "@/components/WelcomeScreen";
import { useExploreTree } from "@/hooks/useExploreTree";
import { useSelection } from "@/hooks/useSelection";

function countDescendants(node: TreeNode): number {
  let count = 0;
  for (const c of node.children) {
    count += 1 + countDescendants(c);
  }
  return count;
}

async function ironViaSSE(
  treeContent: string,
  mode: string,
  instruction?: string
): Promise<string> {
  const nodeId = `iron-${mode}-${Date.now()}`;
  const res = await fetch("/api/flatten", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ treeContent, nodeId, mode, instruction }),
  });

  const reader = res.body?.getReader();
  if (!reader) throw new Error("No response body");

  const decoder = new TextDecoder();
  let buffer = "";
  let result = "";

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;

    buffer += decoder.decode(value, { stream: true });
    const lines = buffer.split("\n\n");
    buffer = lines.pop() || "";

    for (const line of lines) {
      if (!line.startsWith("data: ")) continue;
      const json = JSON.parse(line.slice(6));
      if (json.type === "chunk") result += json.text;
    }
  }

  return result;
}

export default function Home() {
  const [engine, setEngine] = useState<Engine | null>(null);
  const [ironingNodeId, setIroningNodeId] = useState<string | null>(null);
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

  const handleAddNote = useCallback(
    (
      nodeId: string,
      paragraphIndex: number,
      text: string,
      note: string
    ) => {
      tree.addAnnotation(nodeId, paragraphIndex, text, note);
    },
    [tree]
  );

  const handleFlattenResult = useCallback(
    (markdown: string) => {
      const label = "Ironed: " + (tree.rootInput?.slice(0, 30) || "doc");
      tree.newSessionWithResult(label, tree.rootInput || "Ironed document", markdown);
    },
    [tree]
  );

  const handleDeleteNode = useCallback(
    (nodeId: string) => {
      const node = tree.findNode(nodeId);
      if (!node) return;
      if (node.children.length > 0) {
        const count = countDescendants(node);
        if (
          !window.confirm(
            `Delete this branch? ${count} child node${count > 1 ? "s" : ""} will be removed.`
          )
        )
          return;
      }
      tree.deleteNode(nodeId);
    },
    [tree]
  );

  const handleIronNode = useCallback(
    async (nodeId: string, instruction: string, excludeNodeIds: string[]) => {
      const node = tree.findNode(nodeId);
      if (!node || node.children.length === 0) return;

      setIroningNodeId(nodeId);
      try {
        const treeContent = collectSubtreeContent(node, excludeNodeIds);
        const result = await ironViaSSE(treeContent, "iron-down", instruction || undefined);
        tree.replaceWithIron(nodeId, result);
      } catch {
        // Iron failed
      } finally {
        setIroningNodeId(null);
      }
    },
    [tree]
  );

  const handleIronUpNode = useCallback(
    async (nodeId: string, instruction: string, excludeNodeIds: string[]) => {
      const node = tree.findNode(nodeId);
      if (!node || !node.parentId) return;
      const parent = tree.findNode(node.parentId);
      if (!parent) return;

      setIroningNodeId(nodeId);
      try {
        const treeContent = collectIronUpContent(parent, node, excludeNodeIds);
        const result = await ironViaSSE(treeContent, "iron-up", instruction || undefined);
        tree.ironUpNode(nodeId, result);
      } catch {
        // Iron failed
      } finally {
        setIroningNodeId(null);
      }
    },
    [tree]
  );

  const handleEditNode = useCallback(
    (nodeId: string, newMarkdown: string) => {
      tree.editNode(nodeId, newMarkdown);
    },
    [tree]
  );

  if (!engine) {
    return <WelcomeScreen onStart={setEngine} />;
  }

  return (
    <div className="flex flex-1 flex-col bg-zinc-50 pt-8 font-sans dark:bg-zinc-950">
      <header className="drag-region sticky top-0 z-40 border-b border-zinc-200 px-6 py-3 backdrop-blur-sm bg-white/80 dark:border-zinc-800 dark:bg-zinc-900/80">
        <div className="mx-auto flex max-w-3xl items-center justify-between">
          <div className="flex items-center gap-3">
            <h1 className="text-sm font-medium tracking-wide uppercase text-zinc-400 dark:text-zinc-500">
              Undercurrent
            </h1>
            <SessionPicker
              sessions={tree.sessions}
              currentId={tree.currentSessionId}
              onSwitch={tree.switchSession}
              onNew={tree.newSession}
              onDelete={tree.deleteSession}
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
            collapsedIds={tree.collapsedIds}
            onCollapseAll={tree.collapseAll}
            onFlattenResult={handleFlattenResult}
            onImportSession={tree.importSession}
          />
        </div>
      </header>

      <main className="flex-1 overflow-y-auto px-6 py-8">
        <div className="mx-auto max-w-3xl">
          <InputBar
            onSubmit={tree.submitRoot}
            disabled={tree.rootNode?.status === "spawning"}
          />

          {tree.rootNode && (
            <div className="mt-8">
              <div className="mb-4 text-xs text-zinc-400 dark:text-zinc-500 italic">
                {tree.rootInput}
              </div>
              <div className="max-w-3xl">
                <ResponseNode
                  node={tree.rootNode}
                  collapsedIds={tree.collapsedIds}
                  onToggleCollapse={tree.toggleCollapse}
                  onDeleteNode={handleDeleteNode}
                  onIronNode={handleIronNode}
                  onIronUpNode={handleIronUpNode}
                  onEditNode={handleEditNode}
                  ironingNodeId={ironingNodeId}
                />
              </div>
            </div>
          )}

          {!tree.rootNode && (
            <div className="mt-32 text-center text-zinc-400 dark:text-zinc-600">
              <p className="text-6xl mb-4">〰</p>
              <p className="text-xs tracking-widest uppercase text-zinc-300">What&apos;s beneath the surface?</p>
            </div>
          )}
        </div>
      </main>

      <SelectionToolbar
        selection={selection}
        onGoDeeper={handleGoDeeper}
        onAskAbout={handleAskAbout}
        onAddNote={handleAddNote}
        onDismiss={clearSelection}
      />
    </div>
  );
}
