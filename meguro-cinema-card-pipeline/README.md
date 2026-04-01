# Meguro Cinema Card Pipeline

Deterministic Node.js pipeline for:
- accepting normalized Meguro Cinema weekly schedule data
- generating stable Xiaohongshu-ready card images
- exporting both intermediate JSON and final PNG assets

This project is intentionally separated from the Obsidian vault. The vault skill should only call into this project.

## Source of truth

- Product / technical spec: `docs/spec.md`
- Agent entry point: `AGENTS.md`

## Stack

- Node.js
- `satori` for deterministic SVG layout
- `@resvg/resvg-js` for deterministic raster export
- pinned local Noto CJK fonts
- PNG as the final publishing artifact

## Directory layout

- `docs/` specification and contracts
- `src/` renderer / CLI implementation
- `input/` JSON input payloads
- `output/` generated assets

### Archive policy

- keep reusable or historically meaningful weekly inputs under `input/archive/`
- keep generated renders under `output/` for local review only; they are not committed
- when a vault workflow produces a final weekly payload worth retaining, copy the normalized card JSON and optional source-data JSON into `input/archive/`
- treat `input/week.json` as a working input, not the long-term archive

## CLI

Install dependencies:

```bash
pnpm install
```

Render from an input JSON file:

```bash
pnpm run render -- --input input/week.sample.json --out output/sample-week --debug-svg
```

Render the bundled sample:

```bash
pnpm run render:sample
```

## Input contract

The renderer expects a JSON object with:

- `week`
  - `slug`
  - `title`
  - `startDate`
  - `endDate`
  - `timezone`
  - `sourceUrl`
- `cards[]`
  - `slug`
  - `kind`
  - `dateLabel`
  - `weekLabel`
  - `title`
  - `subtitle`
  - `schedule[]`
    - string for simple cover lines, or
    - object with `time`, `title`, optional `meta`, optional `note`
  - `highlights[]`
  - `footer`
  - `palette[]`

See [input/week.sample.json](/Users/pengcheng/projects/charlies-fun-stuff/meguro-cinema-card-pipeline/input/week.sample.json) for a concrete example.

## Stability rules

This project is designed so the same input JSON produces the same output PNGs in the same environment:

- fixed canvas: `1080x1440`
- fixed font files loaded from local `node_modules`
- deterministic truncation limits for titles, schedule rows, and highlight pills
- no runtime randomness
- no remote assets
- optional `input.snapshot.json` written beside outputs for auditability

When metadata is unavailable, pass an empty string instead of placeholder text.
