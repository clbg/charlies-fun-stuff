# Schwab History Data Layer

Generated from Schwab Transaction History.

## Files

- `raw/schwab-transactions-YYYY-MM-DD.csv`: official Schwab CSV export.
- `processed/schwab-transactions-normalized-YYYY-MM-DD.csv`: normalized transactions from official CSV.
- `processed/schwab-transactions-api-sanitized-YYYY-MM-DD.json`: sanitized structured Schwab API rows, with internal IDs removed.
- `processed/schwab-transactions-normalized-YYYY-MM-DD.parquet`: Parquet copy for fast local analytics.
- `processed/schwab-symbol-summary-YYYY-MM-DD.csv`: per-underlying summary.
- `db/schwab-history-YYYY-MM-DD.duckdb`: DuckDB database with transaction and current-account tables.
- `viewer/data.js`: embedded latest data for the static dashboard.

## Core Columns

| Column | Meaning |
|--------|---------|
| `trade_date` | Transaction date shown by Schwab. |
| `asof_date` | Extra settlement/effective date when Schwab shows `as of`. |
| `action` | Schwab action label, e.g. Buy, Sell, Sell to Open. |
| `symbol` | Full Schwab symbol. Options keep contract text. |
| `underlying` | Parsed stock/ETF ticker, useful for grouping. |
| `instrument_type` | `equity_or_etf`, `option`, or `cash`. |
| `option_expiration`, `option_strike`, `option_type` | Parsed option contract fields when available. |
| `quantity`, `price`, `fees_commission`, `amount`, `cash_flow` | Numeric values parsed from Schwab currency/quantity text. |
| `side`, `open_close` | Coarse action classification for analysis. |

## Account State Tables

When a positions export is supplied, the DuckDB file also contains:

| Table | Meaning |
|-------|---------|
| `positions` | Current holdings from the Schwab positions export / Holdings API-derived CSV. |
| `account_summary` | One-row account summary derived from positions. |
| `position_group_summary` | Group totals by Equity / ETF / Option / Cash. |

Important: use `positions` for current holdings and account value. Use `transactions` for historical activity and cash-flow analysis. Do not infer current holdings from transaction history alone.

## Viewer Calendar

`Upcoming Calendar` is derived from the current open-option risk rows embedded in
`viewer/data.js`. Events are grouped by the ISO `expiration` date and use the
snapshot date to calculate remaining calendar days, falling back to API DTE when
the dates are unavailable. The panel shows the nearest six expiration dates.

`Assignment notional` is the strike value represented by current short option
contracts. It is exposure context, not an estimated loss or assignment
probability. Earnings, dividends, macro events, and tax deadlines are not shown
because the current data layer does not provide verified dates for them.

## Suggested Use

```python
import duckdb

con = duckdb.connect("db/schwab-history-YYYY-MM-DD.duckdb")
df = con.sql("select * from transactions where underlying = 'AMZN' order by trade_date").df()
summary = con.sql("select * from symbol_summary order by abs(net_cash_flow) desc").df()
```
