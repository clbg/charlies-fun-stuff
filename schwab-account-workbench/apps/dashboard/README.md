# Schwab Dashboard

React + TypeScript dashboard for the Schwab Account Workbench.

The app bundles the latest vault `viewer/data.js` into
`src/data/portfolio.json` at build time. The production output is a single
self-contained `dist/index.html`, so it can open directly from Finder or
Obsidian without a server.

## Commands

From the repository root, prefer:

```bash
mise run dev
mise run test
mise run build
mise run open
```

From this directory:

```bash
npm run dev
npm run typecheck
npm run test
npm run build
```

## Data Flow

```text
Schwab Trader API
  -> src/schwab_workbench/api_refresh.py
  -> vault Investment/Portfolio/SchwabHistory/viewer/data.js
  -> scripts/dataToJson.mjs
  -> src/data/portfolio.json
  -> dist/index.html
```

## Code Map

- `src/metrics.ts` — pure portfolio math and reconciliation logic.
- `src/selectors.ts` — grouping, allocation, and view selectors.
- `src/calendar.ts` — event calendar model.
- `src/components/` — dashboard panels and chart wrappers.
- `scripts/dataToJson.mjs` — converts vault `viewer/data.js` into bundled JSON.

Generated files:

- `dist/`
- `src/data/portfolio.json`
- `tsconfig.tsbuildinfo`
