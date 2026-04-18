import type { TreeNode } from "./types";
import { unified } from "unified";
import remarkParse from "remark-parse";
import remarkGfm from "remark-gfm";
import remarkRehype from "remark-rehype";
import rehypeStringify from "rehype-stringify";

function mdToHtml(md: string): string {
  const file = unified()
    .use(remarkParse)
    .use(remarkGfm)
    .use(remarkRehype)
    .use(rehypeStringify)
    .processSync(md);
  return String(file);
}

/**
 * Export tree as nested Markdown.
 */
export function exportAsMarkdown(
  rootInput: string,
  rootNode: TreeNode
): string {
  const lines: string[] = [];
  lines.push(`> ${rootInput}\n`);
  lines.push(rootNode.responseMarkdown);

  if (rootNode.children.length > 0) {
    renderChildrenMarkdown(rootNode, lines, 1);
  }

  return lines.join("\n");
}

function renderChildrenMarkdown(
  node: TreeNode,
  lines: string[],
  depth: number
) {
  const indent = "  ".repeat(depth);
  const sortedChildren = [...node.children].sort(
    (a, b) => a.anchorParagraphIndex - b.anchorParagraphIndex
  );

  for (const child of sortedChildren) {
    lines.push("");
    if (child.isAnnotation) {
      lines.push(`${indent}> **Note:** *(on "${child.selectedText.slice(0, 60)}...")*`);
    } else if (child.userQuestion) {
      lines.push(`${indent}> **Q:** ${child.userQuestion}`);
      lines.push(`${indent}> *Selection:* "${child.selectedText.slice(0, 100)}${child.selectedText.length > 100 ? "..." : ""}"`);
    } else {
      lines.push(`${indent}> **↳** "${child.selectedText.slice(0, 100)}${child.selectedText.length > 100 ? "..." : ""}"`);
    }
    lines.push("");

    const responseLines = child.responseMarkdown.split("\n");
    for (const rl of responseLines) {
      lines.push(`${indent}${rl}`);
    }

    if (child.children.length > 0) {
      renderChildrenMarkdown(child, lines, depth + 1);
    }
  }
}

/**
 * Export tree as self-contained HTML with collapsible sections.
 */
export function exportAsHTML(
  rootInput: string,
  rootNode: TreeNode
): string {
  const depthColors = [
    "#60a5fa", "#34d399", "#fbbf24", "#a78bfa",
    "#fb7185", "#22d3ee", "#fb923c", "#f472b6",
  ];

  function renderNode(node: TreeNode, depth: number): string {
    const md = mdToHtml(node.responseMarkdown);
    const children = [...node.children].sort(
      (a, b) => a.anchorParagraphIndex - b.anchorParagraphIndex
    );
    const childrenHtml = children
      .map((c) => {
        const color = c.isAnnotation ? "#d97706" : depthColors[depth % depthColors.length];
        const label = c.isAnnotation
          ? `📝 Note on "${escapeHtml(c.selectedText.slice(0, 60))}..."`
          : c.userQuestion
            ? `Q: ${escapeHtml(c.userQuestion)}`
            : `↳ "${escapeHtml(c.selectedText.slice(0, 80))}${c.selectedText.length > 80 ? "..." : ""}"`;
        return `
          <details class="branch" style="border-left: 2px solid ${color}; margin-left: 16px; padding-left: 16px; margin-top: 8px;">
            <summary style="cursor:pointer; color: #888; font-size: 14px; padding: 4px 0;">${label}</summary>
            <div class="node">${renderNode(c, depth + 1)}</div>
          </details>`;
      })
      .join("\n");

    return `<div class="content">${md}</div>${childrenHtml}`;
  }

  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Undercurrent — ${escapeHtml(rootInput.slice(0, 60))}</title>
<style>
  * { box-sizing: border-box; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    max-width: 720px; margin: 40px auto; padding: 0 20px;
    line-height: 1.6; color: #1a1a1a; background: #fff;
  }
  @media (prefers-color-scheme: dark) {
    body { color: #e5e5e5; background: #0a0a0a; }
    .root-input { background: #1a1a1a; border-color: #333; }
    details summary { color: #888 !important; }
  }
  .root-input {
    background: #f5f5f5; border: 1px solid #e5e5e5;
    border-radius: 8px; padding: 12px 16px; margin-bottom: 24px;
    font-size: 14px; color: #666;
  }
  details summary { list-style: none; }
  details summary::-webkit-details-marker { display: none; }
  details summary::before { content: "▶ "; font-size: 10px; }
  details[open] summary::before { content: "▼ "; }
  .content { font-size: 15px; }
  .content h1 { font-size: 1.4em; font-weight: 700; margin: 1em 0 0.5em; }
  .content h2 { font-size: 1.25em; font-weight: 600; margin: 1em 0 0.4em; }
  .content h3 { font-size: 1.1em; font-weight: 600; margin: 0.8em 0 0.3em; }
  .content p { margin: 0.6em 0; }
  .content ul, .content ol { padding-left: 1.5em; margin: 0.5em 0; }
  .content blockquote { border-left: 3px solid #d1d5db; margin: 0.8em 0; padding: 0.4em 1em; color: #666; }
  .content table { border-collapse: collapse; margin: 0.8em 0; width: 100%; }
  .content th, .content td { border: 1px solid #d1d5db; padding: 6px 12px; text-align: left; }
  .content th { background: #f5f5f5; font-weight: 600; }
  .content pre { background: #f5f5f5; border-radius: 6px; padding: 12px; overflow-x: auto; font-family: monospace; font-size: 0.9em; margin: 0.8em 0; }
  .content code { font-family: monospace; font-size: 0.9em; background: #f0f0f0; padding: 2px 4px; border-radius: 3px; }
  .content pre code { background: none; padding: 0; }
  .content hr { border: none; border-top: 1px solid #e5e5e5; margin: 1.5em 0; }
  .content img { max-width: 100%; }
  @media (prefers-color-scheme: dark) {
    .content blockquote { border-color: #555; color: #aaa; }
    .content th { background: #1a1a1a; }
    .content th, .content td { border-color: #444; }
    .content pre { background: #1a1a1a; }
    .content code { background: #1a1a1a; }
  }
  h1 { font-size: 18px; font-weight: 600; margin-bottom: 16px; }
  .footer { margin-top: 40px; font-size: 12px; color: #999; text-align: center; }
</style>
</head>
<body>
<h1>Undercurrent</h1>
<div class="root-input">${escapeHtml(rootInput)}</div>
${renderNode(rootNode, 0)}
<div class="footer">Generated by Undercurrent</div>
</body>
</html>`;
}

// ── Branch collection for Iron ──────────────────────

function branchLabel(child: TreeNode): string {
  if (child.isAnnotation) return `User note on: "${child.selectedText}"`;
  return child.userQuestion
    ? `Q: ${child.userQuestion} (about: "${child.selectedText}")`
    : `Deep-dive into: "${child.selectedText}"`;
}

function branchTag(child: TreeNode): string {
  return child.isAnnotation ? "user_note" : "branch";
}

function collectBranches(
  node: TreeNode,
  path: string,
  parts: string[],
  excludeIds: Set<string>
) {
  for (const child of node.children) {
    if (excludeIds.has(child.id)) continue;
    const label = branchLabel(child);
    const tag = branchTag(child);
    parts.push(`<${tag} path="${path} → ${label}">\n${child.responseMarkdown}\n</${tag}>\n`);
    collectBranches(child, `${path} → ${label}`, parts, excludeIds);
  }
}

/**
 * Collect all text from the tree for session-level Iron.
 */
export function collectTreeContent(
  rootInput: string,
  rootNode: TreeNode,
  excludeNodeIds: string[] = []
): string {
  const parts: string[] = [];
  const excludeIds = new Set(excludeNodeIds);
  parts.push(`<original>\n${rootInput}\n</original>\n`);
  parts.push(`<root_response>\n${rootNode.responseMarkdown}\n</root_response>\n`);
  collectBranches(rootNode, "root", parts, excludeIds);
  return parts.join("\n");
}

/**
 * Collect content from a subtree for node-level Iron (down).
 */
export function collectSubtreeContent(
  node: TreeNode,
  excludeNodeIds: string[] = []
): string {
  const parts: string[] = [];
  const excludeIds = new Set(excludeNodeIds);

  if (node.userQuestion) {
    parts.push(`<original>\nQ: ${node.userQuestion}\nSelection: "${node.selectedText}"\n</original>\n`);
  } else {
    parts.push(`<original>\nExploring: "${node.selectedText}"\n</original>\n`);
  }

  parts.push(`<root_response>\n${node.responseMarkdown}\n</root_response>\n`);
  collectBranches(node, "root", parts, excludeIds);
  return parts.join("\n");
}

/**
 * Collect content for ironing a child branch up into its parent's response.
 */
export function collectIronUpContent(
  parentNode: TreeNode,
  childNode: TreeNode,
  excludeNodeIds: string[] = []
): string {
  const parts: string[] = [];
  const excludeIds = new Set(excludeNodeIds);

  parts.push(`<parent_response>\n${parentNode.responseMarkdown}\n</parent_response>\n`);

  const selectionContext = childNode.userQuestion
    ? `The user selected "${childNode.selectedText}" and asked: "${childNode.userQuestion}"`
    : childNode.isAnnotation
      ? `The user annotated "${childNode.selectedText}" with their own note`
      : `The user selected "${childNode.selectedText}" to explore deeper`;

  parts.push(`<exploration_context>\n${selectionContext}\n</exploration_context>\n`);

  const tag = childNode.isAnnotation ? "user_note" : "exploration_response";
  parts.push(`<${tag}>\n${childNode.responseMarkdown}\n</${tag}>\n`);

  if (childNode.children.length > 0) {
    collectBranches(childNode, "exploration", parts, excludeIds);
  }

  return parts.join("\n");
}

/**
 * Export session as JSON for import/export round-trip.
 */
export function exportSessionJSON(
  session: { id: string; label: string; rootInput: string; rootNode: TreeNode; collapsedIds: string[] }
): string {
  return JSON.stringify(session, null, 2);
}

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}
