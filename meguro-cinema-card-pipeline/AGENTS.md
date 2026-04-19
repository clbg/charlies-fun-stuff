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
- by default, put generated files under `output/`, but allow the vault skill to override `--out` with an absolute vault path when returning assets to Obsidian
- keep the CLI callable from the vault skill with `pnpm run render -- --input ... --out ...`
- the extra `--` after `pnpm run render` is intentional: it forwards subsequent flags to `node src/cli.mjs`, and the CLI tolerates that separator token explicitly

Before changing renderer behavior, update `docs/spec.md`.
