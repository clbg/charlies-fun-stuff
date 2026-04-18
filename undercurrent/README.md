# Undercurrent

Tree-structured conversation interface. Select text, branch deeper, explore without losing context.

Unlike linear chat where follow-ups scroll to the bottom, Undercurrent lets you select any part of a response and drill into it inline — either automatically or with a specific question. Every branch carries full parent context.

## Quick Start

```bash
./start.sh
```

That's it. The script checks/installs Node.js, pnpm, and Claude CLI, then launches the app and opens your browser.

Already have dependencies? Skip straight to dev:

```bash
pnpm dev
```

> First time? You'll need to run `claude` once in your terminal to login.

## Features

- **Ask or Paste** — type a question or paste text to start exploring
- **Select to Explore** — select any text, choose "Go deeper" or "Ask about this"
- **Inline Expansion** — responses appear nested beneath the selection, not at the bottom
- **Context-Aware** — each branch knows its full ancestry, no repetition
- **Collapse/Expand** — manage complexity with collapsible branches
- **Streaming** — status indicators (Connecting → Thinking → Streaming) with elapsed timer
- **Export** — copy as Markdown or download as self-contained HTML
- **Iron** — merge all branches back into one enriched document
- **Node Iron** — consolidate a single subtree without creating a new session
- **Iron ↑** — merge any branch back into its parent's response
- **Delete Branch** — prune dead ends from the tree
- **Annotations** — select text and add your own notes (amber-styled, separate from AI responses)
- **Inline Editing** — double-click any response to edit it directly (Cmd+Enter to save)
- **Session Persistence** — auto-saves to localStorage, survives refresh
- **Export/Import JSON** — download a session as JSON, import it back later

## Architecture

```
Browser (React/Next.js)          Next.js API Routes
┌─────────────────────┐         ┌──────────────────────┐
│ Select text → toolbar │  SSE   │ spawn('claude',      │
│ Recursive tree nodes  │ ←────→ │   ['-p', prompt])    │
│ Collapse/expand       │        │ Streams stdout → SSE │
└─────────────────────┘         └──────────────────────┘
```

Zero API key — uses Claude CLI's built-in OAuth.

## Testing

```bash
# Browser automation tests (requires browser-use CLI)
bash tests/browser-test.sh
```

## Docs

- [User Stories](docs/user-stories.md)
- [Design](docs/design.md)
- [Packaging & Distribution](docs/packaging.md)
