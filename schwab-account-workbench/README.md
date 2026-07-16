# Schwab Account Workbench

One local workbench for the Schwab account dashboard.

- Code lives here: `~/projects/charlies-fun-stuff/schwab-account-workbench`
- Personal data stays in the Obsidian vault: `Investment/Portfolio/SchwabHistory/`
- The dashboard is a single-file React build that can open from `file://`

## Layout

```text
apps/dashboard/          React + ECharts dashboard
src/schwab_workbench/    Schwab API refresh, auth, DuckDB/viewer data pipeline
docs/                    schema and historical notes
```

Generated data and build artifacts are ignored in git:

```text
apps/dashboard/dist/
apps/dashboard/src/data/portfolio.json
Investment/Portfolio/SchwabHistory/viewer/data.js
Investment/Portfolio/SchwabHistory/db/
Investment/Portfolio/SchwabHistory/processed/
```

## Install

```bash
cd ~/projects/charlies-fun-stuff/schwab-account-workbench
mise trust
mise run install
```

## Daily Refresh

```bash
cd ~/projects/charlies-fun-stuff/schwab-account-workbench
mise run refresh
mise run build
mise run publish
```

This refreshes Schwab API data into the vault, rebuilds the dashboard, then
copies the single-file dashboard back to the vault.

## Open

Fastest:

```bash
cd ~/projects/charlies-fun-stuff/schwab-account-workbench
mise run open
```

That rebuilds and opens:

```text
~/projects/charlies-fun-stuff/schwab-account-workbench/apps/dashboard/dist/index.html
```

For live development:

```bash
mise run dev
```

Then open the Vite URL printed in the terminal, usually
`http://127.0.0.1:5173/`.

Vault artifact after `mise run publish`:

```text
Investment/Portfolio/SchwabHistory/viewer-react/dist/index.html
```

## Useful Commands

```bash
mise run auth        # create/check Schwab OAuth token
mise run smoke       # read-only sanitized API smoke test
mise run refresh     # refresh data into the vault
mise run test        # dashboard typecheck + tests
mise run build       # build single-file dashboard
mise run open        # build and open local dashboard
mise run publish     # copy built dashboard to the vault
```

## Secrets

Schwab API credentials and optional external API keys are read from environment
variables, the vault `.env`, or Bitwarden Secrets Manager. Never commit tokens,
raw auth headers, account IDs, `posId`, or `prestoData`.
