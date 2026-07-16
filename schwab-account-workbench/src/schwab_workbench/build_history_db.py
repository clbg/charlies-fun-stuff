#!/usr/bin/env python3
import argparse
import csv
import json
import re
from datetime import datetime
from pathlib import Path

import duckdb
import pandas as pd

from .common import HISTORY_ROOT


MONEY_RE = re.compile(r"^\(?-?\$?[\d,]+(?:\.\d+)?\)?$")
OPTION_RE = re.compile(
    r"^(?P<underlying>[A-Z.]+)\s+"
    r"(?P<expiration>\d{2}/\d{2}/\d{4})\s+"
    r"(?P<strike>\d+(?:\.\d+)?)\s+"
    r"(?P<option_type>[CP])$"
)


def parse_money(value):
    if value is None:
        return None
    text = str(value).strip()
    if not text:
        return None
    negative = text.startswith("-") or (text.startswith("(") and text.endswith(")"))
    text = text.replace("$", "").replace(",", "").replace("(", "").replace(")", "").replace("-", "")
    if not text:
        return None
    try:
        number = float(text)
    except ValueError:
        return None
    return -number if negative else number


def parse_quantity(value):
    if value is None:
        return None
    text = str(value).strip().replace(",", "")
    if not text:
        return None
    try:
        return float(text)
    except ValueError:
        return None


def parse_percent(value):
    if value is None:
        return None
    text = str(value).strip().replace("%", "").replace(",", "")
    if not text:
        return None
    try:
        return float(text)
    except ValueError:
        return None


def split_transaction_date(value):
    text = str(value or "").strip()
    if " as of " in text:
        date_text, asof_text = text.split(" as of ", 1)
    else:
        date_text, asof_text = text, ""
    return parse_date(date_text), parse_date(asof_text)


def parse_date(value):
    text = str(value or "").strip()
    if not text:
        return None
    for fmt in ("%m/%d/%Y", "%Y-%m-%d"):
        try:
            return datetime.strptime(text, fmt).date().isoformat()
        except ValueError:
            pass
    return None


def parse_symbol(symbol):
    symbol = str(symbol or "").strip()
    match = OPTION_RE.match(symbol)
    if match:
        data = match.groupdict()
        return {
            "symbol": symbol,
            "underlying": data["underlying"],
            "instrument_type": "option",
            "option_expiration": parse_date(data["expiration"]),
            "option_strike": float(data["strike"]),
            "option_type": "CALL" if data["option_type"] == "C" else "PUT",
        }
    return {
        "symbol": symbol,
        "underlying": symbol if symbol else None,
        "instrument_type": "cash" if not symbol else "equity_or_etf",
        "option_expiration": None,
        "option_strike": None,
        "option_type": None,
    }


def classify_action(action):
    text = str(action or "").lower()
    if "buy" in text:
        side = "buy"
    elif "sell" in text:
        side = "sell"
    else:
        side = "non_trade"
    open_close = None
    if "open" in text:
        open_close = "open"
    elif "close" in text:
        open_close = "close"
    return side, open_close


def load_csv(path):
    rows = []
    with Path(path).open(newline="", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        for idx, row in enumerate(reader, start=1):
            trade_date, asof_date = split_transaction_date(row.get("Date"))
            symbol_info = parse_symbol(row.get("Symbol"))
            quantity = parse_quantity(row.get("Quantity"))
            price = parse_money(row.get("Price"))
            fees = parse_money(row.get("Fees & Comm"))
            amount = parse_money(row.get("Amount"))
            side, open_close = classify_action(row.get("Action"))
            rows.append(
                {
                    "source": "official_csv",
                    "source_row": idx,
                    "trade_date": trade_date,
                    "asof_date": asof_date,
                    "action": row.get("Action", "").strip(),
                    "symbol": symbol_info["symbol"],
                    "underlying": symbol_info["underlying"],
                    "instrument_type": symbol_info["instrument_type"],
                    "option_expiration": symbol_info["option_expiration"],
                    "option_strike": symbol_info["option_strike"],
                    "option_type": symbol_info["option_type"],
                    "description": row.get("Description", "").strip(),
                    "quantity": quantity,
                    "price": price,
                    "fees_commission": fees,
                    "amount": amount,
                    "cash_flow": amount,
                    "side": side,
                    "open_close": open_close,
                }
            )
    return rows


def load_api(path):
    if not path:
        return []
    raw = json.loads(Path(path).read_text())
    if isinstance(raw, list):
        return raw
    rows = []
    for idx, row in enumerate(raw.get("brokerageTransactions", []), start=1):
        trade_date, asof_date = split_transaction_date(row.get("transactionDate"))
        symbol_info = parse_symbol(row.get("symbol"))
        side, open_close = classify_action(row.get("action"))
        detail = row.get("transactionDetail") or {}
        rows.append(
            {
                "source": "schwab_api",
                "source_row": idx,
                "trade_date": trade_date,
                "asof_date": asof_date,
                "action": str(row.get("action", "")).strip(),
                "symbol": symbol_info["symbol"],
                "underlying": symbol_info["underlying"],
                "instrument_type": symbol_info["instrument_type"],
                "option_expiration": symbol_info["option_expiration"],
                "option_strike": symbol_info["option_strike"],
                "option_type": symbol_info["option_type"],
                "description": str(row.get("description", "")).strip(),
                "quantity": parse_quantity(row.get("shareQuantity")),
                "price": parse_money(row.get("executionPrice")),
                "fees_commission": parse_money(row.get("feesAndCommission")),
                "amount": parse_money(row.get("amount")),
                "cash_flow": parse_money(row.get("amount")),
                "side": side,
                "open_close": open_close,
                "settle_date": parse_date(detail.get("settleDate")),
                "principal": parse_money(detail.get("principal")),
                "commission": parse_money(detail.get("commission")),
                "exchange_processing_fee": parse_money(detail.get("exchangeProcessingFee")),
                "secondary_fee": parse_money(detail.get("secondaryFee")),
                "source_code": str(row.get("sourceCode", "")).strip(),
            }
        )
    return rows


def load_positions(path, snapshot_date):
    if not path:
        return []
    rows = []
    with Path(path).open(newline="", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        for idx, row in enumerate(reader, start=1):
            ticker = str(row.get("Ticker", "")).strip()
            group = str(row.get("Group", "")).strip()
            parent = str(row.get("Parent", "")).strip()
            underlying = parent or (ticker.split(" ")[0] if group == "Option" else ticker)
            rows.append(
                {
                    "snapshot_date": snapshot_date,
                    "source_row": idx,
                    "ticker": ticker,
                    "underlying": underlying,
                    "description": str(row.get("Description", "")).strip(),
                    "group_name": group,
                    "parent": parent or None,
                    "quantity": parse_quantity(row.get("Qty")),
                    "price": parse_money(row.get("Price")),
                    "market_value": parse_money(row.get("Market Value")),
                    "day_change": parse_money(row.get("Day Change")),
                    "day_change_pct": parse_percent(row.get("Day Change %")),
                    "cost_basis": parse_money(row.get("Cost Basis")),
                    "gain_loss": parse_money(row.get("Gain/Loss")),
                    "gain_loss_pct": parse_percent(row.get("Gain/Loss %")),
                    "weight": parse_percent(row.get("Weight")),
                }
            )
    return rows


def summarize_positions(positions):
    total_value = sum(row["market_value"] or 0 for row in positions)
    long_value = sum(row["market_value"] or 0 for row in positions if row["group_name"] != "Option")
    option_value = sum(row["market_value"] or 0 for row in positions if row["group_name"] == "Option")
    cash_value = sum(row["market_value"] or 0 for row in positions if row["group_name"] == "Cash")
    day_change = sum(row["day_change"] or 0 for row in positions)
    cost_basis = sum(row["cost_basis"] or 0 for row in positions)
    gain_loss = sum(row["gain_loss"] or 0 for row in positions)
    return {
        "account_value": total_value,
        "long_market_value": long_value,
        "option_market_value": option_value,
        "cash_value": cash_value,
        "day_change": day_change,
        "cost_basis": cost_basis,
        "gain_loss": gain_loss,
        "position_rows": len(positions),
    }


def write_viewer_data(path, tx_csv, summary_csv, positions_csv, date, account_summary):
    payload = {
        "date": date,
        "transactions_csv": Path(tx_csv).read_text(encoding="utf-8"),
        "summary_csv": Path(summary_csv).read_text(encoding="utf-8"),
        "positions_csv": Path(positions_csv).read_text(encoding="utf-8") if positions_csv else "",
        "account_summary": account_summary,
    }
    Path(path).write_text(
        "\n".join(
            [
                f"window.SCHWAB_DATA_META = {json.dumps({'date': date, 'account_summary': account_summary}, ensure_ascii=False)};",
                f"window.SCHWAB_TX_CSV = {json.dumps(payload['transactions_csv'], ensure_ascii=False)};",
                f"window.SCHWAB_SUMMARY_CSV = {json.dumps(payload['summary_csv'], ensure_ascii=False)};",
                f"window.SCHWAB_POSITIONS_CSV = {json.dumps(payload['positions_csv'], ensure_ascii=False)};",
                "",
            ]
        ),
        encoding="utf-8",
    )


def write_schema(path):
    path.write_text(
        """# Schwab History Data Layer

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

## Suggested Use

```python
import duckdb

con = duckdb.connect("db/schwab-history-YYYY-MM-DD.duckdb")
df = con.sql("select * from transactions where underlying = 'AMZN' order by trade_date").df()
summary = con.sql("select * from symbol_summary order by abs(net_cash_flow) desc").df()
```
""",
        encoding="utf-8",
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--date", required=True)
    parser.add_argument("--csv", required=True)
    parser.add_argument("--api-json")
    parser.add_argument("--positions-csv")
    parser.add_argument("--viewer-data", default=str(HISTORY_ROOT / "viewer" / "data.js"))
    parser.add_argument("--out-dir", default=str(HISTORY_ROOT))
    parser.add_argument(
        "--write-viewer",
        action="store_true",
        help=(
            "Overwrite viewer/data.js with the legacy SCHWAB_TX_CSV schema. "
            "The current viewer reads SCHWAB_API_* instead, so leave this OFF "
            "unless you are intentionally reverting to the old CSV-only dashboard."
        ),
    )
    args = parser.parse_args()

    root = Path(args.out_dir)
    processed = root / "processed"
    db_dir = root / "db"
    processed.mkdir(parents=True, exist_ok=True)
    db_dir.mkdir(parents=True, exist_ok=True)

    csv_rows = load_csv(args.csv)
    tx = pd.DataFrame(csv_rows)
    tx["trade_date"] = pd.to_datetime(tx["trade_date"], errors="coerce")
    tx["asof_date"] = pd.to_datetime(tx["asof_date"], errors="coerce")
    tx["option_expiration"] = pd.to_datetime(tx["option_expiration"], errors="coerce")

    normalized_csv = processed / f"schwab-transactions-normalized-{args.date}.csv"
    normalized_parquet = processed / f"schwab-transactions-normalized-{args.date}.parquet"
    tx.to_csv(normalized_csv, index=False)
    tx.to_parquet(normalized_parquet, index=False)

    api_rows = load_api(args.api_json) if args.api_json else []
    sanitized_api_path = processed / f"schwab-transactions-api-sanitized-{args.date}.json"
    sanitized_api_path.write_text(json.dumps(api_rows, indent=2, ensure_ascii=False), encoding="utf-8")

    trade_actions = tx[tx["side"].isin(["buy", "sell"])].copy()
    summary = (
        trade_actions.groupby(["underlying", "instrument_type"], dropna=False)
        .agg(
            transaction_count=("symbol", "count"),
            first_trade_date=("trade_date", "min"),
            last_trade_date=("trade_date", "max"),
            gross_buys=("amount", lambda s: float(s[s < 0].sum())),
            gross_sells=("amount", lambda s: float(s[s > 0].sum())),
            total_fees=("fees_commission", "sum"),
            net_cash_flow=("cash_flow", "sum"),
            total_quantity=("quantity", "sum"),
        )
        .reset_index()
    )
    summary_csv = processed / f"schwab-symbol-summary-{args.date}.csv"
    summary.to_csv(summary_csv, index=False)

    positions_rows = load_positions(args.positions_csv, args.date) if args.positions_csv else []
    positions = pd.DataFrame(positions_rows)
    account_summary = summarize_positions(positions_rows)
    account_summary_df = pd.DataFrame([{ "snapshot_date": args.date, **account_summary }])
    if positions_rows:
        group_summary = (
            positions.groupby("group_name", dropna=False)
            .agg(
                rows=("ticker", "count"),
                market_value=("market_value", "sum"),
                day_change=("day_change", "sum"),
                cost_basis=("cost_basis", "sum"),
                gain_loss=("gain_loss", "sum"),
            )
            .reset_index()
        )
    else:
        group_summary = pd.DataFrame(columns=["group_name", "rows", "market_value", "day_change", "cost_basis", "gain_loss"])

    db_path = db_dir / f"schwab-history-{args.date}.duckdb"
    if db_path.exists():
        db_path.unlink()
    con = duckdb.connect(str(db_path))
    con.register("tx_df", tx)
    con.execute("create table transactions as select * from tx_df")
    con.register("summary_df", summary)
    con.execute("create table symbol_summary as select * from summary_df")
    con.register("positions_df", positions)
    con.execute("create table positions as select * from positions_df")
    con.register("account_summary_df", account_summary_df)
    con.execute("create table account_summary as select * from account_summary_df")
    con.register("group_summary_df", group_summary)
    con.execute("create table position_group_summary as select * from group_summary_df")
    con.close()

    if args.write_viewer:
        # schema.md documents the live API viewer; only rewrite it with the legacy
        # schema when explicitly reverting the dashboard alongside the viewer.
        write_schema(root / "schema.md")
    if args.positions_csv and args.write_viewer:
        write_viewer_data(args.viewer_data, normalized_csv, summary_csv, args.positions_csv, args.date, account_summary)
    elif args.positions_csv:
        print(
            "skipped viewer/data.js write: legacy SCHWAB_TX_CSV schema is incompatible "
            "with the current viewer. Pass --write-viewer to force the old dashboard.",
            flush=True,
        )

    print(f"transactions={len(tx)}")
    print(f"api_rows={len(api_rows)}")
    print(f"positions={len(positions_rows)}")
    print(f"normalized_csv={normalized_csv}")
    print(f"normalized_parquet={normalized_parquet}")
    print(f"summary_csv={summary_csv}")
    print(f"duckdb={db_path}")
    print(f"schema={root / 'schema.md'}")
    if args.positions_csv and args.write_viewer:
        print(f"viewer_data={args.viewer_data}")


if __name__ == "__main__":
    main()
