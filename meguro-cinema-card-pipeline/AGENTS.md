# Meguro Cinema Card Pipeline

Read `docs/spec.md` first.

This directory is the source of truth for the Meguro Cinema rendering pipeline.
The Obsidian vault skill should not re-define rendering rules that belong here.

When working in this project:
- prefer Node.js over Python
- treat PNG export as the final target artifact
- keep rendering deterministic: same input JSON should produce the same output files
- define all inputs via JSON contracts, not ad hoc prompt text
- put implementation under `src/`
- put generated files under `output/`
- keep the CLI callable from the vault skill with `pnpm run render -- --input ... --out ...`

Before changing renderer behavior, update `docs/spec.md`.
