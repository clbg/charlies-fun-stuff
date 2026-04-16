# User Stories — Undercurrent

## Vision

A tree-structured conversation interface. Unlike linear chat (where follow-ups scroll to the bottom), Undercurrent lets you select any part of a response and branch into it — either drilling deeper automatically or asking a specific question. Every branch carries full parent context, creating a navigable knowledge tree rooted in your original question or text.

**Platform: Desktop browsers only (MVP).** No mobile support.

---

## Core Stories (MVP)

### US-1: Ask or Paste
**As a** user,
**I want to** type a question or paste a block of text as my starting point,
**so that** I can begin exploring any topic.

**Acceptance Criteria:**
- Single input area at the top, accepts both questions and pasted text
- Submit triggers an LLM response that renders as rich text (markdown) below
- First-time experience: placeholder hint "Ask a question or paste text to explore..."
- Validates input: rejects empty/whitespace-only
- MVP engine: Claude CLI only (`claude -p`)

### US-2: Select to Explore
**As a** user,
**I want to** select a portion of any response text and have the option to drill deeper,
**so that** I can explore whatever catches my attention — on my terms.

**Acceptance Criteria:**
- User selects text within any response node (native browser text selection)
- A floating toolbar appears near the selection with two actions:
  - **"Go deeper"** — auto-generates a drill-down based on selection + parent context
  - **"Ask about this"** — opens an inline input field for a custom follow-up question
- Toolbar disappears when selection is cleared or user clicks elsewhere
- Works at any depth level in the tree
- Selection disabled on nodes that are currently streaming (US-7)
- Selection enabled on all completed sibling/parent nodes regardless of other nodes' streaming state

### US-3: Inline Expansion
**As a** user,
**I want to** see the drill-down or answer appear inline beneath the selected text,
**so that** I stay in context rather than scrolling to a new message.

**Acceptance Criteria:**
- **Insertion rule**: the expansion attaches after the paragraph containing the **start** of the selection. If selection spans multiple paragraphs, anchor to the first.
- If a user selects a single word mid-paragraph, the expansion still goes after that paragraph (not mid-paragraph)
- Multiple expansions on the same paragraph stack vertically in creation order
- Each nested block is visually indented to show parent-child relationship
- The nested response is itself rich text — can be selected for further branching
- Smooth expand animation (height transition)
- Shows a loading indicator while waiting for response

### US-4: Context-Aware Responses
**As a** user,
**I want to** have each drill-down aware of the full conversation path above it,
**so that** explanations are relevant and non-repetitive.

**Acceptance Criteria:**
- Each request to the LLM includes the context chain: root input → parent responses → current selection
- Context chain truncation strategy (see TS-2 for algorithm)
- Responses should not re-explain concepts already covered in parent nodes

### US-5: Expand / Collapse Any Node
**As a** user,
**I want to** freely expand and collapse any branch in my exploration tree,
**so that** I can manage visual complexity.

**Acceptance Criteria:**
- Each expanded node has a collapse toggle (chevron or similar)
- Collapsing hides all children but preserves their state in memory
- "Collapse all" button available
- Previously expanded content preserved on re-expand (no re-fetch)
- Keyboard: Enter to expand, Esc to collapse
- Soft depth limit at 8 levels — shows "Continue deeper?" prompt beyond that
- MVP is ephemeral: refreshing the page loses the tree (persistence is US-12)

### US-6: Error Handling
**As a** user,
**I want to** see clear error messages when something goes wrong,
**so that** I can understand and recover from failures.

**Acceptance Criteria:**
- CLI not found: "Claude CLI not found. Install with `npm i -g @anthropic-ai/claude-code`"
- Auth expired: "Authentication expired. Run `claude` in terminal to re-login"
- Timeout (>30s): "Request timed out. Click to retry"
- Malformed output: render as plain text, no crash
- Each error shown inline at the node that failed, with a retry button
- Abort in-flight requests when collapsing a loading node

### US-7: Streaming Output with Status Feedback
**As a** user,
**I want to** see what's happening behind the scenes and see responses stream in progressively,
**so that** I know the app hasn't frozen and can follow along as text generates.

**Acceptance Criteria:**
- Status phases displayed: Connecting → Thinking → Streaming → Done
- Elapsed time counter shown during Connecting and Thinking phases
- Blinking cursor at the end of streaming text
- Text appears chunk-by-chunk as the CLI outputs it (SSE)
- Selection/branching is enabled only after stream completes **for that specific node**
- Other completed nodes remain selectable while a sibling is streaming
- Abort stream when user collapses a node mid-stream

### US-8: Export as Markdown
**As a** user,
**I want to** copy my exploration tree as nested Markdown,
**so that** I can paste it into notes, docs, or other tools.

**Acceptance Criteria:**
- "Copy MD" button in toolbar
- Outputs nested blockquotes for branches with the selected text as header
- Copies to clipboard with one click

### US-9: Export as HTML
**As a** user,
**I want to** download my exploration tree as a self-contained HTML file,
**so that** I can share it with others or open it offline.

**Acceptance Criteria:**
- "Export HTML" button in toolbar
- Generates a single HTML file with embedded CSS
- Uses `<details>` elements for collapsible branches
- Works offline, no external dependencies
- Respects dark mode via `prefers-color-scheme`

### US-10: Iron / Flatten → New Session
**As a** user,
**I want to** merge all my exploration branches back into the original response as one cohesive document,
**so that** I get an enriched, linear article that incorporates all the deeper insights.

**Acceptance Criteria:**
- "Iron" button in toolbar (disabled if no branches exist)
- Calls the LLM to weave branch content into the root response
- Iron result becomes a **new session** (not a modal) — the enriched text is auto-submitted as the new root
- The original exploration session is preserved and accessible via session picker
- The new session can be further explored (select text, drill deeper, Iron again)

### US-11: Session Management
**As a** user,
**I want to** manage multiple exploration sessions,
**so that** I can switch between topics and revisit past explorations.

**Acceptance Criteria:**
- Session picker dropdown in header (shows session label + branch count)
- "+ New session" button in the dropdown
- Sessions labeled by first ~40 chars of root input
- Switching sessions preserves all state (tree, collapsed nodes)
- Iron creates a new session prefixed "Ironed: ..."

### US-12: Fast Model for Drill-Down
**As a** user,
**I want** drill-down responses to be fast,
**so that** exploration feels fluid.

**Acceptance Criteria:**
- Root questions use the default model (Opus — deep, thorough)
- Drill-down ("Go deeper" / "Ask about this") uses `--model sonnet` (faster)
- No user configuration needed — automatic based on depth

### US-13: Welcome Screen & Engine Selection
**As a** user,
**I want to** see a setup screen before starting,
**so that** I can confirm my engine is ready and choose what to use.

**Acceptance Criteria:**
- Welcome screen shown on first load
- Detects available engines (Claude CLI) and shows status (ready / not found)
- "Start Exploring" button to enter main UI
- Engine badge in header — click to return to welcome screen

### US-14: Desktop App (Electron)
**As a** user,
**I want to** run Undercurrent as a native desktop app,
**so that** I can double-click to launch without using the terminal.

**Acceptance Criteria:**
- `pnpm dist` produces a `.dmg` for macOS (arm64 + x64)
- App detects Claude CLI availability at startup (with full shell PATH resolution)
- Embedded Next.js standalone server starts automatically
- Custom app icon (wave motif)

---

## Enhancement Stories (Post-MVP)

### US-15: Multi-Engine Support
Choose between Claude, Gemini, Codex, Copilot CLIs. Engine adapter pattern with auto-detection.

### US-16: Exploration Minimap
A sidebar or breadcrumb showing the full tree structure for orientation in deep explorations.

### US-17: Custom Persona / Context
Set a system-level context like "explain at a high-school level" or "focus on code examples" that applies to all responses.

### US-18: Session Persistence
Save exploration state to localStorage so refreshing doesn't lose work.

---

## Technical Stories (Internal)

### TS-1: Prompt Engineering & Output Format
- "Go deeper" prompt: given context chain + selected text, generate an explanation
- "Ask about this" prompt: given context chain + selected text + user question, generate an answer
- Root requests use default model; drill-down uses `--model sonnet` for speed
- Output is plain text/markdown (no special markers needed since user drives selection)
- Handle multi-paragraph responses gracefully

### TS-2: Context Chain Management
- Each node stores: its response text, its parent reference, the selection that spawned it, the user question (if any)
- When building a prompt, walk up the tree to assemble context
- **Truncation algorithm**:
  1. Always include **root input** in full
  2. Always include **immediate parent node** response in full
  3. Always include **current selection** + user question in full
  4. Middle layers (between root and parent): include only the selected text that spawned each node (not the full response), forming a "selection breadcrumb trail"
  5. If total still exceeds ~4000 tokens, summarize middle layer selections to one line each
  6. Branching is independent: node A→B→C and node A→D have separate context chains. D's context does NOT include B or C.

### TS-3: Process Lifecycle Management
- Max 3 concurrent CLI spawns; additional requests queued (UX reason: prevent overwhelming the local machine and CLI rate limits)
- Collapse triggers SIGTERM to CLI child process, which closes the SSE stream (single mechanism for US-5 + US-7)
- Clean up zombie processes on server shutdown (SIGTERM handler)
- Kill all child processes on page unload (beforeunload → API call)

---

## Technical Constraints

- **Platform**: Desktop browsers only (Chrome, Firefox, Safari)
- **Backend**: Node.js (Next.js API routes), `child_process.spawn` to `claude -p`
- **Frontend**: React (Next.js), single-page app
- **Auth**: Zero API key — CLI's built-in OAuth
- **Deployment**: Runs locally (`npm run dev`)
- **Streaming**: Server-Sent Events (SSE) from API routes to frontend
- **MVP Engine**: Claude CLI only; multi-engine via adapter pattern later
