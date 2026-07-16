---
title: Schwab Transaction History Export 2026-07-14
date: 2026-07-14
type: portfolio-history-export
tags:
  - schwab
  - portfolio
  - quant-data
---

# Summary

Exported Schwab Transaction History for Individual (...360).

| Metric | Value |
|--------|-------|
| Official CSV rows | 661 |
| Schwab page/API result rows | 200 |
| Date range in database | 2022-07-28 to 2026-07-14 |
| Official page search range | 2022-07-14 to 2026-07-14 |
| DuckDB database | `Investment/Portfolio/SchwabHistory/db/schwab-history-2026-07-14.duckdb` |

# Files

| File | Purpose |
|------|---------|
| `raw/schwab-transactions-2026-07-14.csv` | Official Schwab CSV export. Primary source. |
| `processed/schwab-transactions-normalized-2026-07-14.csv` | Clean transaction table for pandas/polars. |
| `processed/schwab-transactions-normalized-2026-07-14.parquet` | Fast local analytics copy. |
| `processed/schwab-transactions-api-sanitized-2026-07-14.json` | Sanitized API response subset for comparison. |
| `processed/schwab-symbol-summary-2026-07-14.csv` | Per-underlying transaction summary. |
| `db/schwab-history-2026-07-14.duckdb` | DuckDB database with `transactions` and `symbol_summary`. |
| `schema.md` | Column definitions and example queries. |

# Notes

- The official CSV exported more rows than the page/API returned. Use the official CSV-derived `transactions` table as the primary source.
- The structured API response was saved only after removing internal order/issue identifiers and retaining analysis fields.
- No trades or order tickets were opened.
- This is transaction history, not a full realized/unrealized P&L engine yet. Per-stock analysis should next join:
  - transaction cash flows from this database;
  - current holdings from the latest Schwab snapshot;
  - optional market price history for time-series return analysis.

# Quick Queries

```python
import duckdb

con = duckdb.connect("Investment/Portfolio/SchwabHistory/db/schwab-history-2026-07-14.duckdb")

amzn = con.sql("""
select *
from transactions
where underlying = 'AMZN'
order by trade_date
""").df()

summary = con.sql("""
select *
from symbol_summary
order by abs(net_cash_flow) desc
""").df()
```

# Initial Counts

| Instrument Type | Rows | Net Cash Flow |
|-----------------|------|---------------|
| equity_or_etf | 494 | -$56,271.16 |
| cash | 118 | +$54,206.36 |
| option | 49 | +$3,063.15 |

