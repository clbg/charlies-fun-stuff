# Design — Undercurrent

## Architecture

```
Browser (React)                    Next.js Server
┌─────────────────────┐           ┌─────────────────────────┐
│                     │  POST     │ /api/explore            │
│  <ExploreRoot>      │ ───────→  │   { engine, context[] , │
│    <ResponseNode>   │           │     selection, question }│
│      <ResponseNode> │  SSE      │                         │
│        ...          │ ←──────── │   spawn('claude',       │
│                     │  chunks   │     ['-p', prompt])      │
│  <SelectionToolbar> │           │   pipe stdout → SSE     │
└─────────────────────┘           └─────────────────────────┘
```

## Data Model

```typescript
interface TreeNode {
  id: string;                    // nanoid
  parentId: string | null;       // null = root
  anchorParagraphIndex: number;  // which paragraph this expands from
  selectedText: string;          // what the user selected
  userQuestion?: string;         // "Ask about this" question, if any
  responseMarkdown: string;      // LLM response (grows during streaming)
  children: TreeNode[];          // nested expansions
  status: 'spawning' | 'thinking' | 'streaming' | 'done' | 'error';
  error?: string;
  startedAt?: number;            // Date.now() when request started
  isAnnotation?: boolean;        // true = user-authored note, not AI response
}

interface Session {
  id: string;                    // nanoid
  label: string;                 // first ~40 chars of rootInput
  rootInput: string | null;      // original question or pasted text
  rootNode: TreeNode | null;     // first response tree
  collapsedIds: Set<string>;     // which nodes are collapsed
}
// Sessions managed by useExploreTree hook. Iron creates a new session.
// Persisted to localStorage on every mutation; loaded on app startup.
```

## Component Tree

```
<App>
  <WelcomeScreen />                // engine selection (US-13)
  — or after engine chosen: —
  <Header>
    <SessionPicker />              // dropdown to switch sessions (US-11)
    <EngineBadge />                // click to switch engine
    <Toolbar />                    // Collapse all | Copy MD | Export HTML | Iron
  </Header>
  <InputBar />                     // top-level input (US-1)
  <ResponseNode node={root}>       // recursive component
    <StatusIndicator />            // Connecting/Thinking + elapsed timer (US-7)
    <Markdown content={node.responseMarkdown} />
    {childrenAtParagraph.map(child =>
      <CollapsibleBlock>           // expand/collapse wrapper (US-5)
        <ResponseNode node={child} />  // recurse
      </CollapsibleBlock>
    )}
  </ResponseNode>
  <SelectionToolbar />             // floating: Go deeper | Ask about this | Add note (US-2, US-22)
```

## API Contract

### POST /api/explore

**Request:**
```json
{
  "engine": "claude",
  "context": [
    { "role": "root", "text": "original input" },
    { "role": "selection-trail", "text": "selected → selected → ..." },
    { "role": "parent", "text": "immediate parent full response" }
  ],
  "selection": "the text user selected",
  "question": "optional user question",
  "fast": true,
  "nodeId": "abc123"
}
```
- `fast: true` → uses `--model sonnet` (drill-down). Omitted for root questions (uses default Opus).
- `nodeId` → tracks the spawned process for abort.

**Response:** SSE stream
```
data: {"type":"status","status":"spawning"}
data: {"type":"status","status":"thinking"}
data: {"type":"chunk","text":"The concept of..."}
data: {"type":"chunk","text":" quantum entanglement..."}
data: {"type":"done"}
```
or
```
data: {"type":"error","message":"CLI not found"}
```

### POST /api/flatten

Iron/flatten endpoint. Takes tree content (collected from all branches), returns SSE stream of the merged document. Used for both session-level Iron (all branches → new session) and node-level Iron (subtree branches → replaces node's response in-place).

### GET /api/engines

Returns engine availability: `{ "claude": true }`

## Key Decisions

1. **Markdown split by paragraph**: `ResponseNode` splits `responseMarkdown` by `\n\n` into paragraphs. Child nodes attach after their `anchorParagraphIndex`. This is how inline expansion works.

2. **SelectionToolbar positioning**: Use `window.getSelection()` + `getRangeAt(0).getBoundingClientRect()` to position the floating toolbar near the selection. Disappears on `mousedown` outside or selection change.

3. **Context building**: Walk up the tree from current node to root. Include root input + selection breadcrumbs + parent response (truncation per TS-2).

4. **Streaming**: API route spawns `claude -p`, reads stdout, converts to SSE with status phases (spawning → thinking → streaming → done). Frontend appends chunks to `node.responseMarkdown`.

5. **Process management**: Track spawned processes by node ID. On collapse or abort, SIGTERM the child process.

6. **Fast model for drill-down**: Root questions use default model (Opus). Drill-down uses `--model sonnet` for faster responses. Controlled by `fast` flag in API request.

7. **Sessions**: Multiple sessions managed in `useExploreTree`. Iron creates a new session with the flattened text as root input (auto-submitted). Sessions auto-persist to localStorage on every mutation (debounced 500ms) and restore on page load.

9. **Delete node**: Removes a node and all its descendants. Confirmation dialog shown when node has children. Cannot delete root node.

10. **Node-level Iron**: Available on any node with children (all in "done" status). Collects subtree content, sends to `/api/flatten`, replaces node's `responseMarkdown` with the ironed result and removes all children. Does NOT create a new session — mutates in-place.

11. **Iron ↑ (merge into parent)**: Any non-root node can be ironed upward — its response (and any sub-branches) are woven into the parent's `responseMarkdown`, and the node is removed. Uses a dedicated prompt template via `mode: "iron-up"` on `/api/flatten`.

12. **Annotations**: User-authored notes attached to selected text. Created via "Add note" in the selection toolbar. Stored as `TreeNode` with `isAnnotation: true`, `status: "done"`, no LLM call. Rendered with amber border and 📝 prefix. Included as `<user_note>` tags during Iron to preserve the user's voice.

13. **Inline editing**: Double-click any response node to enter edit mode (textarea). Cmd+Enter saves, Escape cancels. Works on both AI responses and annotations.

14. **Export/Import JSON**: Export a full session (tree + collapsedIds) as `.json` file. Import creates a new session from the file. Enables round-trip archival.

15. **Iron with instructions**: `/api/flatten` accepts an optional `instruction` parameter appended to the prompt (e.g., "keep it concise", "academic tone"). Supported for all Iron modes.

8. **Electron packaging**: `output: "standalone"` builds a minimal Next.js server. `server-bundle/` contains the dereferenced (no symlinks) standalone output. Electron `main.js` resolves the user's full shell PATH before spawning node/claude.

## File Structure

```
undercurrent/
├── package.json
├── next.config.ts
├── electron-builder.yml
├── start.sh                      // one-click launcher
├── electron/
│   └── main.js                   // Electron main process
├── scripts/
│   └── build-app.js              // pnpm dist → .dmg
├── tests/
│   ├── browser-test.sh           // browser automation tests
│   └── dmg-test.sh               // DMG install+launch tests
├── docs/
│   ├── user-stories.md
│   ├── design.md
│   └── packaging.md
├── src/
│   ├── app/
│   │   ├── layout.tsx
│   │   ├── page.tsx              // sessions + routing
│   │   ├── globals.css
│   │   └── api/
│   │       ├── explore/route.ts  // POST: spawn CLI → SSE
│   │       ├── flatten/route.ts  // POST: Iron → SSE
│   │       └── engines/route.ts  // GET: detect available CLIs
│   ├── components/
│   │   ├── InputBar.tsx
│   │   ├── ResponseNode.tsx      // recursive tree node
│   │   ├── CollapsibleBlock.tsx
│   │   ├── SelectionToolbar.tsx
│   │   ├── StatusIndicator.tsx   // Connecting/Thinking + timer
│   │   ├── SessionPicker.tsx     // session dropdown
│   │   ├── Toolbar.tsx           // Collapse/Export/Iron/Import
│   │   ├── IronPanel.tsx         // Iron config: instructions + branch selection
│   │   └── WelcomeScreen.tsx     // engine selection
│   ├── lib/
│   │   ├── engine.ts             // CLI spawn + fast model option
│   │   ├── context.ts            // context chain builder
│   │   ├── export.ts             // Markdown + HTML export
│   │   ├── prompt.ts             // prompt templates
│   │   └── types.ts
│   └── hooks/
│       ├── useExploreTree.ts     // tree state + session management + localStorage persistence
│       └── useSelection.ts       // text selection detection
```
