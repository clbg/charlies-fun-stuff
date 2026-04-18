export interface TreeNode {
  id: string;
  parentId: string | null;
  anchorParagraphIndex: number;
  selectedText: string;
  userQuestion?: string;
  responseMarkdown: string;
  children: TreeNode[];
  status: "spawning" | "thinking" | "streaming" | "done" | "error";
  error?: string;
  startedAt?: number;
  isAnnotation?: boolean;
}

export type Engine = "claude";

export interface ExploreRequest {
  engine: Engine;
  context: ContextEntry[];
  selection: string;
  question?: string;
  /** "haiku" for go-deeper, "sonnet" for ask-about, undefined for root (opus) */
  model?: "haiku" | "sonnet";
}

export interface ContextEntry {
  role: "root" | "selection-trail" | "parent";
  text: string;
}

export type SSEEvent =
  | { type: "status"; status: "spawning" | "thinking" }
  | { type: "chunk"; text: string }
  | { type: "done" }
  | { type: "error"; message: string };
