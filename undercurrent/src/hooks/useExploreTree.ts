"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { nanoid } from "nanoid";
import type { TreeNode, ContextEntry } from "@/lib/types";
import { buildContext } from "@/lib/context";

export interface Session {
  id: string;
  label: string;
  rootInput: string | null;
  rootNode: TreeNode | null;
  collapsedIds: Set<string>;
}

export interface ExploreTree {
  // Session management
  sessions: Session[];
  currentSessionId: string;
  switchSession: (id: string) => void;
  newSession: () => void;
  /** Create a new session pre-filled with text (used by Iron) */
  newSessionFrom: (label: string, text: string) => void;

  // Current session state
  rootInput: string | null;
  rootNode: TreeNode | null;
  collapsedIds: Set<string>;
  submitRoot: (input: string) => void;
  addChild: (
    parentId: string,
    anchorParagraphIndex: number,
    selectedText: string,
    question?: string
  ) => void;
  toggleCollapse: (nodeId: string) => void;
  collapseAll: () => void;
  findNode: (id: string) => TreeNode | undefined;
}

function makeSession(): Session {
  return {
    id: nanoid(),
    label: "New",
    rootInput: null,
    rootNode: null,
    collapsedIds: new Set(),
  };
}

export function useExploreTree(): ExploreTree {
  const [sessions, setSessions] = useState<Session[]>(() => [makeSession()]);
  const [currentSessionId, setCurrentSessionId] = useState(
    () => sessions[0].id
  );

  // Mutable ref for findNode (avoids stale closures)
  const sessionsRef = useRef(sessions);
  sessionsRef.current = sessions;

  const getCurrent = useCallback(
    () =>
      sessionsRef.current.find((s) => s.id === currentSessionId) ??
      sessionsRef.current[0],
    [currentSessionId]
  );

  // ── Session management ────────────────────────────

  const switchSession = useCallback((id: string) => {
    setCurrentSessionId(id);
  }, []);

  const newSession = useCallback(() => {
    const s = makeSession();
    setSessions((prev) => [...prev, s]);
    setCurrentSessionId(s.id);
  }, []);

  const newSessionFrom = useCallback((label: string, text: string) => {
    const s = makeSession();
    s.label = label;
    s.rootInput = text;
    setSessions((prev) => [...prev, s]);
    setCurrentSessionId(s.id);
    // Auto-submit will be triggered by effect below
  }, []);

  // ── Tree helpers ──────────────────────────────────

  const updateSession = useCallback(
    (updater: (s: Session) => Session) => {
      setSessions((prev) =>
        prev.map((s) => (s.id === currentSessionId ? updater(s) : s))
      );
    },
    [currentSessionId]
  );

  const updateNode = useCallback(
    (nodeId: string, updater: (node: TreeNode) => TreeNode) => {
      updateSession((s) => {
        if (!s.rootNode) return s;
        return { ...s, rootNode: deepUpdateNode(s.rootNode, nodeId, updater) };
      });
    },
    [updateSession]
  );

  const findNodeInTree = useCallback(
    (node: TreeNode | null, id: string): TreeNode | undefined => {
      if (!node) return undefined;
      if (node.id === id) return node;
      for (const child of node.children) {
        const found = findNodeInTree(child, id);
        if (found) return found;
      }
      return undefined;
    },
    []
  );

  const findNode = useCallback(
    (id: string) => findNodeInTree(getCurrent().rootNode, id),
    [findNodeInTree, getCurrent]
  );

  // ── Streaming ─────────────────────────────────────

  const startStream = useCallback(
    (
      node: TreeNode,
      context: ContextEntry[],
      selection: string,
      question?: string,
      model?: "haiku" | "sonnet"
    ) => {
      fetch("/api/explore", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          engine: "claude",
          context,
          selection,
          question,
          model,
          nodeId: node.id,
        }),
      })
        .then(async (res) => {
          const reader = res.body?.getReader();
          if (!reader) throw new Error("No response body");

          const decoder = new TextDecoder();
          let buffer = "";

          while (true) {
            const { done, value } = await reader.read();
            if (done) break;

            buffer += decoder.decode(value, { stream: true });
            const lines = buffer.split("\n\n");
            buffer = lines.pop() || "";

            for (const line of lines) {
              if (!line.startsWith("data: ")) continue;
              const json = JSON.parse(line.slice(6));

              if (json.type === "status") {
                updateNode(node.id, (n) => ({
                  ...n,
                  status: json.status,
                }));
              } else if (json.type === "chunk") {
                updateNode(node.id, (n) => ({
                  ...n,
                  responseMarkdown: n.responseMarkdown + json.text,
                  status: "streaming",
                }));
              } else if (json.type === "done") {
                updateNode(node.id, (n) => ({ ...n, status: "done" }));
              } else if (json.type === "error") {
                updateNode(node.id, (n) => ({
                  ...n,
                  status: "error",
                  error: json.message,
                }));
              }
            }
          }
        })
        .catch((err) => {
          if (err.name === "AbortError") return;
          updateNode(node.id, (n) => ({
            ...n,
            status: "error",
            error: err.message,
          }));
        });
    },
    [updateNode]
  );

  // ── Actions ───────────────────────────────────────

  const submitRoot = useCallback(
    (input: string) => {
      const node: TreeNode = {
        id: nanoid(),
        parentId: null,
        anchorParagraphIndex: 0,
        selectedText: input,
        responseMarkdown: "",
        children: [],
        status: "spawning",
        startedAt: Date.now(),
      };
      updateSession((s) => ({
        ...s,
        rootInput: input,
        rootNode: node,
        label: input.slice(0, 40) + (input.length > 40 ? "..." : ""),
        collapsedIds: new Set(),
      }));

      const context: ContextEntry[] = [{ role: "root", text: input }];
      startStream(node, context, input);
    },
    [updateSession, startStream]
  );

  // Auto-submit for sessions created via newSessionFrom
  const current = getCurrent();
  const autoSubmitRef = useRef<string | null>(null);
  useEffect(() => {
    if (
      current.rootInput &&
      !current.rootNode &&
      autoSubmitRef.current !== current.id
    ) {
      autoSubmitRef.current = current.id;
      submitRoot(current.rootInput);
    }
  }, [current.id, current.rootInput, current.rootNode, submitRoot]);

  const addChild = useCallback(
    (
      parentId: string,
      anchorParagraphIndex: number,
      selectedText: string,
      question?: string
    ) => {
      const child: TreeNode = {
        id: nanoid(),
        parentId,
        anchorParagraphIndex,
        selectedText,
        userQuestion: question,
        responseMarkdown: "",
        children: [],
        status: "spawning",
        startedAt: Date.now(),
      };

      updateNode(parentId, (parent) => ({
        ...parent,
        children: [...parent.children, child],
      }));

      const context = buildContext(current.rootInput!, child, findNode);
      // Go deeper → haiku (fast), Ask about → sonnet (better reasoning)
      startStream(child, context, selectedText, question, question ? "sonnet" : "haiku");
    },
    [updateNode, startStream, current.rootInput, findNode]
  );

  const toggleCollapse = useCallback(
    (nodeId: string) => {
      updateSession((s) => {
        const next = new Set(s.collapsedIds);
        if (next.has(nodeId)) next.delete(nodeId);
        else next.add(nodeId);
        return { ...s, collapsedIds: next };
      });
    },
    [updateSession]
  );

  const collapseAll = useCallback(() => {
    updateSession((s) => {
      if (!s.rootNode) return s;
      const ids = new Set<string>();
      const collect = (node: TreeNode) => {
        if (node.children.length > 0) ids.add(node.id);
        node.children.forEach(collect);
      };
      collect(s.rootNode);
      return { ...s, collapsedIds: ids };
    });
  }, [updateSession]);

  return {
    sessions,
    currentSessionId,
    switchSession,
    newSession,
    newSessionFrom,
    rootInput: current.rootInput,
    rootNode: current.rootNode,
    collapsedIds: current.collapsedIds,
    submitRoot,
    addChild,
    toggleCollapse,
    collapseAll,
    findNode,
  };
}

function deepUpdateNode(
  node: TreeNode,
  targetId: string,
  updater: (n: TreeNode) => TreeNode
): TreeNode {
  if (node.id === targetId) return updater(node);
  const updatedChildren = node.children.map((child) =>
    deepUpdateNode(child, targetId, updater)
  );
  if (updatedChildren === node.children) return node;
  return { ...node, children: updatedChildren };
}
