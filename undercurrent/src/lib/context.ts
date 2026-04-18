import type { TreeNode, ContextEntry } from "./types";

/**
 * Walk up the tree from a node to root, building the context chain.
 *
 * Strategy (from TS-2):
 * 1. Root input always included in full
 * 2. Immediate parent response in full
 * 3. Middle layers: only the selectedText that spawned each node (breadcrumb trail)
 */
export function buildContext(
  rootInput: string,
  targetNode: TreeNode,
  findNode: (id: string) => TreeNode | undefined
): ContextEntry[] {
  // Walk up to collect ancestors
  const ancestors: TreeNode[] = [];
  let current: TreeNode | undefined = targetNode;
  while (current?.parentId) {
    const parent = findNode(current.parentId);
    if (parent) ancestors.push(parent);
    current = parent;
  }
  ancestors.reverse(); // now [closest-to-root ... immediate-parent]

  const entries: ContextEntry[] = [
    { role: "root", text: rootInput },
  ];

  if (ancestors.length > 1) {
    // Middle layers: selection breadcrumb trail
    const middle = ancestors.slice(0, -1);
    const trail = middle.map((n) => n.selectedText).join(" → ");
    entries.push({ role: "selection-trail", text: trail });
  }

  if (ancestors.length > 0) {
    // Immediate parent in full
    const parent = ancestors[ancestors.length - 1];
    entries.push({ role: "parent", text: parent.responseMarkdown });
  }

  return entries;
}
