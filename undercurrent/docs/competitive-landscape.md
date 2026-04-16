# Competitive Landscape — Undercurrent

> Last updated: 2026-04-13

## One-line positioning

**Prose-native AI exploration editor: inline recursive expansion + ancestor-aware branching + synthesis back into prose.**

In plain language: select any sentence in an article, drill deeper in-place, then iron all branches back into one enriched document.

## Market finding

As of April 2026, **no public product combines all five core features**:
1. In-reply arbitrary text selection → inline recursive expansion
2. Persistent collapsible tree structure
3. Automatic ancestor context inheritance
4. One-click "Iron" — merge branches back into original prose
5. Native export as nested Markdown / self-contained collapsible HTML

Existing products split into three non-overlapping camps:

| Camp | Representatives | What they do | What Undercurrent adds |
|------|----------------|--------------|----------------------|
| **Canvas / branching chat** | Flowith, Thinkvas, Twigg, Chatvas, OXPT | Fork conversations on a canvas/node graph | Branches grow **from within the prose**, not on a separate canvas |
| **Inline selection explainer** | Claeva, BranchAI, Dobby AI, Explainpaper, Semantic Reader | Select text → get a one-off explanation or popup | Each drill-down becomes a **persistent, collapsible, comparable, mergeable branch** |
| **Git-like merge / squash** | Promptree, GitChat, Methodox Threads | Branch/merge conversation nodes | "Iron" **back-fills into the original linear text**, preserving paragraph structure |

## Closest competitors

### Tier 1 — Most similar (2+ feature overlap)

**Claeva** (claeva.com) — Closest to feature #1. "Select any text in a reply and keep asking at different depths." No public evidence of persistent tree, context inheritance, branch merge, or structured export. Status: live product page.

**Thinkvas AI** (thinkvas.ai) — Closest to features #2 and #3. "Fork at any turn, full context inheritance, canvas view." But canvas-first, not prose-first inline expansion. Status: public beta.

**OXPT** (oxpt.online) — "Visual branching prompt tree, synthesize liked paths into better results." Spiritually close to #2 and #4, but prompt-tree/canvas oriented, not prose-first. Status: live online tool.

**Flowith** (flowith.io) — Multi-threaded canvas, branching and consolidation, Composer integration. Close to #2 and #4. Core is node/canvas workflow, not inline text exploration. Status: live product.

**Promptree** (github.com/Leniolabs/promptree) — Git semantics for LLM conversations: branch, merge, squash into single Q&A. Close to #4. Entry point is message-level, not text-fragment-level. Status: open source prototype.

### Tier 2 — Partial overlap (1 feature)

| Product | Overlap | Gap |
|---------|---------|-----|
| Twigg | Tree visualization, context control | Not inline expansion |
| Chatvas (Chat Nodes Canvas) | Branch visualization on canvas | ChatGPT wrapper, not native |
| Methodox Threads | Markdown export, hierarchy | Editor hierarchy, not inline exploration |
| BranchAI (Chrome ext) | Select text → inline ask | Ephemeral popups, no persistent tree |
| Dobby AI (Chrome ext) | In-page bubble follow-ups | No tree, no merge |
| Explainpaper | Highlight → explanation + follow-up | Not branching tree |
| Semantic Reader | In-line citation cards, contextual overlays | Augmented reading, not branching |

## Academic research

Key papers validating this direction:

- **Qlarify (UIST 2024)** — Recursively expandable abstracts via brushing/selecting. Closest academic precedent to feature #1. [arXiv:2310.07581](https://arxiv.org/abs/2310.07581)
- **Mindalogue (2024)** — Non-linear node+canvas interaction for complex tasks, reduces steps vs linear chat. [arXiv:2410.10570](https://arxiv.org/abs/2410.10570)
- **ContextBranch (2025)** — Version control for LLM conversations. Branch isolation reduces context pollution (31→13 messages). Validates feature #3. [arXiv:2512.13914](https://arxiv.org/abs/2512.13914)
- **TreeReader (2025)** — Interactive tree for papers: concise summary first, expand on demand. [arXiv:2507.18945](https://arxiv.org/pdf/2507.18945)
- **CitePeek (CUI 2025)** — Surface/deep dive levels for citations. [ACM DL](https://dl.acm.org/doi/10.1145/3719160.3737639)
- **"LLMs Get Lost In Multi-Turn Conversation" (2025)** — Evidence that LLMs degrade in long linear conversations. Branching with context isolation is not just better UX — it's better for model performance. [arXiv:2505.06120](https://arxiv.org/html/2505.06120v1)

## Differentiation strategy

### Where to press

1. **Prose-first, not canvas-first** — Users face continuous text; branches grow from within it. This is the sharpest visual and conceptual distinction vs Flowith/Thinkvas/Twigg.
2. **Persistent structure from inline actions** — Every drill-down leaves a collapsible, revisitable, comparable branch. Not a popup that disappears.
3. **Iron as the killer feature** — "Explore → Iron → Publish" as a closed loop. No competitor clearly articulates "merge branches back into the original text's paragraph structure."
4. **Branch-native export** — Treating the exploration tree itself as a first-class exportable artifact (nested MD, collapsible HTML).

### Where not to compete

- Don't position as "another AI chat" or "another AI canvas"
- Don't try to be a general-purpose writing tool
- Don't compete on model selection breadth — focus on the interaction paradigm
