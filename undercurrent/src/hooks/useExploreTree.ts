"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { nanoid } from "nanoid";
import type { TreeNode, ContextEntry } from "@/lib/types";
import { buildContext } from "@/lib/context";

// ── Persistence ─────────────────────────────────────

const STORAGE_KEY = "undercurrent-sessions";
const SESSION_ID_KEY = "undercurrent-current-session";

interface SerializedSession {
  id: string;
  label: string;
  rootInput: string | null;
  rootNode: TreeNode | null;
  collapsedIds: string[];
}

function serializeSessions(sessions: Session[]): string {
  const serialized: SerializedSession[] = sessions.map((s) => ({
    ...s,
    collapsedIds: [...s.collapsedIds],
  }));
  return JSON.stringify(serialized);
}

function deserializeSessions(json: string): Session[] {
  const parsed: SerializedSession[] = JSON.parse(json);
  return parsed.map((s) => ({
    ...s,
    collapsedIds: new Set(s.collapsedIds),
    rootNode: s.rootNode ? sanitizeRestoredNode(s.rootNode) : null,
  }));
}

function sanitizeRestoredNode(node: TreeNode): TreeNode {
  return {
    ...node,
    status:
      node.status === "done" || node.status === "error"
        ? node.status
        : "done",
    children: node.children.map(sanitizeRestoredNode),
  };
}

// ── Tree helpers (module-level) ─────────────────────

function findInTree(
  node: TreeNode | null,
  id: string
): TreeNode | undefined {
  if (!node) return undefined;
  if (node.id === id) return node;
  for (const child of node.children) {
    const found = findInTree(child, id);
    if (found) return found;
  }
  return undefined;
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
  if (updatedChildren.every((c, i) => c === node.children[i])) return node;
  return { ...node, children: updatedChildren };
}

function deepDeleteNode(node: TreeNode, targetId: string): TreeNode {
  const filtered = node.children.filter((c) => c.id !== targetId);
  if (filtered.length !== node.children.length) {
    return { ...node, children: filtered };
  }
  const updated = node.children.map((c) => deepDeleteNode(c, targetId));
  if (updated.every((c, i) => c === node.children[i])) return node;
  return { ...node, children: updated };
}

function collectDescendantIds(node: TreeNode): Set<string> {
  const ids = new Set<string>();
  for (const c of node.children) {
    ids.add(c.id);
    for (const id of collectDescendantIds(c)) ids.add(id);
  }
  return ids;
}

// ── Types ───────────────────────────────────────────

export interface Session {
  id: string;
  label: string;
  rootInput: string | null;
  rootNode: TreeNode | null;
  collapsedIds: Set<string>;
}

export interface ExploreTree {
  sessions: Session[];
  currentSessionId: string;
  switchSession: (id: string) => void;
  newSession: () => void;
  newSessionFrom: (label: string, text: string) => void;
  deleteSession: (id: string) => void;

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
  deleteNode: (nodeId: string) => void;
  replaceWithIron: (nodeId: string, markdown: string) => void;
  ironUpNode: (nodeId: string, newParentMarkdown: string) => void;
  addAnnotation: (
    parentId: string,
    anchorParagraphIndex: number,
    selectedText: string,
    note: string
  ) => void;
  editNode: (nodeId: string, newMarkdown: string) => void;
  importSession: (json: string) => void;
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

// ── Hook ────────────────────────────────────────────

export function useExploreTree(): ExploreTree {
  const [sessions, setSessions] = useState<Session[]>(() => [makeSession()]);
  const [currentSessionId, setCurrentSessionId] = useState(
    () => sessions[0].id
  );

  const sessionsRef = useRef(sessions);
  sessionsRef.current = sessions;

  const getCurrent = useCallback(
    () =>
      sessionsRef.current.find((s) => s.id === currentSessionId) ??
      sessionsRef.current[0],
    [currentSessionId]
  );

  // ── Persistence: load ─────────────────────────────

  useEffect(() => {
    try {
      const stored = localStorage.getItem(STORAGE_KEY);
      if (!stored) return;
      const restored = deserializeSessions(stored);
      if (restored.length === 0) return;
      setSessions(restored);
      const savedId = localStorage.getItem(SESSION_ID_KEY);
      if (savedId && restored.some((s) => s.id === savedId)) {
        setCurrentSessionId(savedId);
      } else {
        setCurrentSessionId(restored[0].id);
      }
    } catch {
      // Corrupt data — start fresh
    }
  }, []);

  // ── Persistence: save (debounced) ─────────────────

  useEffect(() => {
    const timeout = setTimeout(() => {
      try {
        localStorage.setItem(STORAGE_KEY, serializeSessions(sessions));
        localStorage.setItem(SESSION_ID_KEY, currentSessionId);
      } catch {
        // Storage full or unavailable
      }
    }, 500);
    return () => clearTimeout(timeout);
  }, [sessions, currentSessionId]);

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
  }, []);

  const deleteSession = useCallback(
    (id: string) => {
      setSessions((prev) => {
        if (prev.length <= 1) {
          // Can't delete the last session — replace with a fresh one
          const fresh = makeSession();
          setCurrentSessionId(fresh.id);
          return [fresh];
        }
        const next = prev.filter((s) => s.id !== id);
        // If we're deleting the current session, switch to a neighbor
        if (id === currentSessionId) {
          const oldIndex = prev.findIndex((s) => s.id === id);
          const newIndex = Math.min(oldIndex, next.length - 1);
          setCurrentSessionId(next[newIndex].id);
        }
        return next;
      });
    },
    [currentSessionId]
  );

  // ── Tree state helpers ────────────────────────────

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

  const findNode = useCallback(
    (id: string) => findInTree(getCurrent().rootNode, id),
    [getCurrent]
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
      startStream(
        child,
        context,
        selectedText,
        question,
        question ? "sonnet" : "haiku"
      );
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

  const deleteNode = useCallback(
    (nodeId: string) => {
      updateSession((s) => {
        if (!s.rootNode || s.rootNode.id === nodeId) return s;
        const target = findInTree(s.rootNode, nodeId);
        if (!target) return s;
        const idsToRemove = collectDescendantIds(target);
        idsToRemove.add(nodeId);
        const newCollapsed = new Set(s.collapsedIds);
        for (const id of idsToRemove) newCollapsed.delete(id);
        return {
          ...s,
          rootNode: deepDeleteNode(s.rootNode, nodeId),
          collapsedIds: newCollapsed,
        };
      });
    },
    [updateSession]
  );

  const replaceWithIron = useCallback(
    (nodeId: string, markdown: string) => {
      updateSession((s) => {
        if (!s.rootNode) return s;
        const target = findInTree(s.rootNode, nodeId);
        if (!target) return s;
        const descendantIds = collectDescendantIds(target);
        const newRoot = deepUpdateNode(s.rootNode, nodeId, (n) => ({
          ...n,
          responseMarkdown: markdown,
          children: [],
          status: "done" as const,
        }));
        const newCollapsed = new Set(s.collapsedIds);
        for (const id of descendantIds) newCollapsed.delete(id);
        newCollapsed.delete(nodeId);
        return { ...s, rootNode: newRoot, collapsedIds: newCollapsed };
      });
    },
    [updateSession]
  );

  const ironUpNode = useCallback(
    (nodeId: string, newParentMarkdown: string) => {
      updateSession((s) => {
        if (!s.rootNode) return s;
        const target = findInTree(s.rootNode, nodeId);
        if (!target || !target.parentId) return s;
        const parentId = target.parentId;
        const descendantIds = collectDescendantIds(target);
        descendantIds.add(nodeId);
        let newRoot = deepUpdateNode(s.rootNode, parentId, (parent) => ({
          ...parent,
          responseMarkdown: newParentMarkdown,
          children: parent.children.filter((c) => c.id !== nodeId),
        }));
        const newCollapsed = new Set(s.collapsedIds);
        for (const id of descendantIds) newCollapsed.delete(id);
        return { ...s, rootNode: newRoot, collapsedIds: newCollapsed };
      });
    },
    [updateSession]
  );

  const addAnnotation = useCallback(
    (
      parentId: string,
      anchorParagraphIndex: number,
      selectedText: string,
      note: string
    ) => {
      const child: TreeNode = {
        id: nanoid(),
        parentId,
        anchorParagraphIndex,
        selectedText,
        responseMarkdown: note,
        children: [],
        status: "done",
        isAnnotation: true,
      };
      updateNode(parentId, (parent) => ({
        ...parent,
        children: [...parent.children, child],
      }));
    },
    [updateNode]
  );

  const editNode = useCallback(
    (nodeId: string, newMarkdown: string) => {
      updateNode(nodeId, (n) => ({
        ...n,
        responseMarkdown: newMarkdown,
      }));
    },
    [updateNode]
  );

  const importSession = useCallback(
    (json: string) => {
      const data = JSON.parse(json);
      const s: Session = {
        id: nanoid(),
        label: data.label || "Imported",
        rootInput: data.rootInput,
        rootNode: data.rootNode ? sanitizeRestoredNode(data.rootNode) : null,
        collapsedIds: new Set(data.collapsedIds || []),
      };
      setSessions((prev) => [...prev, s]);
      setCurrentSessionId(s.id);
    },
    []
  );

  return {
    sessions,
    currentSessionId,
    switchSession,
    newSession,
    newSessionFrom,
    deleteSession,
    rootInput: current.rootInput,
    rootNode: current.rootNode,
    collapsedIds: current.collapsedIds,
    submitRoot,
    addChild,
    toggleCollapse,
    collapseAll,
    findNode,
    deleteNode,
    replaceWithIron,
    ironUpNode,
    addAnnotation,
    editNode,
    importSession,
  };
}
