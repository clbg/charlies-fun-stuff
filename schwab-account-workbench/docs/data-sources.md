# Schwab Workbench Data Sources

Updated: 2026-07-16

This document is the source of truth for data providers, secret names, and
fallback behavior used by the Schwab Account Workbench.

## Secret Loading

Runtime secrets are loaded in this order:

1. Existing environment variables.
2. The vault `.env` file.
3. Bitwarden Secrets Manager via `bws`.

The vault `.env` should contain `BWS_ACCESS_TOKEN` if Bitwarden Secrets Manager
is used. Secret values must never be committed, printed, or copied into notes.

Check configuration without printing values:

```bash
cd ~/projects/charlies-fun-stuff/schwab-account-workbench
mise run auth -- --check-only
```

## Core Provider

| Provider | Purpose | Required secrets | Output |
| --- | --- | --- | --- |
| Schwab Trader API | Source of truth for balances, current positions, quotes, price history, recent transactions, option chains, and option risk. | `SCHWAB_TRADER_CLIENT_ID`, `SCHWAB_TRADER_CLIENT_SECRET`, `SCHWAB_TRADER_CALLBACK_URL` | `account_snapshots`, `position_snapshots`, `market_quotes`, `market_prices_daily`, `recent_transactions_api`, `option_chains`, `option_position_risk` |

Schwab OAuth token storage:

```text
$CODEX_HOME/secrets/schwab-trader-token.json
```

Never store the OAuth token in the vault or git repo.

The Schwab Developer Portal app provides Client ID, Client Secret, and Callback
URL. Product access should include Accounts and Trading Production plus Market
Data Production.

## Optional Enrichment Providers

| Provider | Purpose | Secret name | Fallback when missing |
| --- | --- | --- | --- |
| Alpha Vantage | Upcoming earnings calendar for held equities. | `ALPHAVANTAGE_API_KEY` or `ALPHA_VANTAGE_API_KEY` | Uses Alpha Vantage `demo`; if rate-limited or invalid, earnings are skipped. |
| SEC EDGAR | Recent company filings for held equities. | None. Optional `SEC_USER_AGENT`. | Uses default local User-Agent. |
| FRED | Macro release dates / economic calendar. | `FRED_API_KEY` | Keeps local FOMC calendar only. |
| CoinGecko | BTC reference data for crypto ETF context. | `COINGECKO_API_KEY` or `CG_DEMO_API_KEY` | Attempts public endpoint; may be rate-limited. |
| Finnhub | Analyst recommendation summary and recent company headlines. | `FINNHUB_API_KEY` | Marks Finnhub as skipped; dashboard panel may be empty. |

## Browser Fallback Secrets

Browser login fallback is separate from Trader API OAuth. Use only when the
Schwab web session is unavailable and the user is supervising the login.

| Purpose | Secret name |
| --- | --- |
| Schwab web login username | `SCHWAB_USERNAME` |
| Schwab web login password | `SCHWAB_PASSWORD` |

Do not use `SCHWAB_CLIENT_ID` or `SCHWAB_CLIENT_SECRET` for web login. Those
names are ambiguous and are not used by this workbench.

## Data Boundaries

- Current holdings, balances, current quantities, and unrealized P&L come from
  Schwab Trader API account and position snapshots.
- Recent activity comes from Schwab Trader API transactions.
- Full historical trades, cash flow, transfers, dividends, and fees still come
  from archived normalized CSV files because Schwab transaction history is a
  recent-window API.
- The dashboard reads the generated vault `viewer/data.js`; it does not call
  provider APIs directly in the browser.

## Generated Artifacts

```text
Investment/Portfolio/SchwabHistory/viewer/data.js
Investment/Portfolio/SchwabHistory/db/schwab-api-YYYY-MM-DD.duckdb
Investment/Portfolio/SchwabHistory/processed/schwab-api-raw-sanitized-YYYY-MM-DD.json
Investment/Portfolio/SchwabHistory/viewer-react/dist/index.html
```

Sanitization rules:

- Keep only masked account tails.
- Never persist bearer tokens, authorization headers, full account IDs,
  `hashValue`, `posId`, `prestoData`, or raw OAuth token payloads.
- Keep raw API responses only after sanitizer processing.
