#!/usr/bin/env python3
"""Read-only Schwab Trader API refresh into DuckDB.

This is the new primary data-capture path for account state and market data.
It deliberately does not import order builders and never calls order mutation
endpoints.
"""

from __future__ import annotations

import argparse
import csv
import io
import json
import re
import time
from datetime import date, datetime, timedelta
from pathlib import Path

import duckdb
import httpx
import pandas as pd
from schwab.auth import client_from_token_file
from schwab.client import Client

from .common import HISTORY_ROOT, load_credentials, mask_tail, sanitize_api_payload, token_path


OPTION_DESC_RE = re.compile(r"(?P<expiration>\d{2}/\d{2}/\d{4})\s+\$(?P<strike>\d+(?:\.\d+)?)\s+(?P<put_call>Put|Call)", re.I)

SEC_CIK_FALLBACK = {
    "AAPL": {"cik_str": 320193, "ticker": "AAPL", "title": "Apple Inc."},
    "AMZN": {"cik_str": 1018724, "ticker": "AMZN", "title": "Amazon.com, Inc."},
    "GLW": {"cik_str": 24741, "ticker": "GLW", "title": "Corning Inc."},
    "GOOG": {"cik_str": 1652044, "ticker": "GOOG", "title": "Alphabet Inc."},
    "GOOGL": {"cik_str": 1652044, "ticker": "GOOGL", "title": "Alphabet Inc."},
    "INTC": {"cik_str": 50863, "ticker": "INTC", "title": "Intel Corp."},
    "MCD": {"cik_str": 63908, "ticker": "MCD", "title": "McDonald's Corp."},
    "META": {"cik_str": 1326801, "ticker": "META", "title": "Meta Platforms, Inc."},
    "MU": {"cik_str": 723125, "ticker": "MU", "title": "Micron Technology, Inc."},
    "NVDA": {"cik_str": 1045810, "ticker": "NVDA", "title": "NVIDIA Corp."},
    "QCOM": {"cik_str": 804328, "ticker": "QCOM", "title": "QUALCOMM Inc."},
    "SE": {"cik_str": 1703399, "ticker": "SE", "title": "Sea Ltd."},
    "TSLA": {"cik_str": 1318605, "ticker": "TSLA", "title": "Tesla, Inc."},
}


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--date", default=date.today().isoformat())
    parser.add_argument("--token-path", help="Override local token path.")
    parser.add_argument("--out-dir", default=str(HISTORY_ROOT))
    parser.add_argument("--lookback-days", type=int, default=59, help="Recent Schwab transaction lookback. API currently allows about 60 days.")
    parser.add_argument("--price-history-days", type=int, default=370)
    parser.add_argument("--skip-option-chains", action="store_true")
    parser.add_argument("--skip-earnings", action="store_true", help="Skip the external earnings-calendar fetch.")
    parser.add_argument("--skip-sec", action="store_true", help="Skip SEC EDGAR submissions enrichment.")
    parser.add_argument("--skip-fred", action="store_true", help="Skip FRED macro calendar enrichment.")
    parser.add_argument("--skip-coingecko", action="store_true", help="Skip CoinGecko BTC reference enrichment.")
    parser.add_argument("--skip-finnhub", action="store_true", help="Skip Finnhub news/recommendation enrichment.")
    parser.add_argument("--viewer-data", default=str(HISTORY_ROOT / "viewer" / "data.js"))
    return parser.parse_args()


def ok_json(response):
    if response.status_code != httpx.codes.OK:
        response.raise_for_status()
    return response.json()


def account_tail(securities_account):
    raw = securities_account.get("acct_tail") or securities_account.get("accountNumber") or ""
    return mask_tail(str(raw)) if raw else ""


def parse_option_fields(instrument):
    description = instrument.get("description") or ""
    match = OPTION_DESC_RE.search(description)
    if not match:
        return None, None
    expiration = datetime.strptime(match.group("expiration"), "%m/%d/%Y").date().isoformat()
    strike = float(match.group("strike"))
    return expiration, strike


def flatten_accounts(accounts_payload, snapshot_date):
    rows = []
    for idx, account in enumerate(accounts_payload if isinstance(accounts_payload, list) else [], start=1):
        acct = account.get("securitiesAccount") or {}
        balances = acct.get("currentBalances") or {}
        rows.append({
            "snapshot_date": snapshot_date,
            "source_row": idx,
            "account_tail": account_tail(acct),
            "account_type": acct.get("type"),
            "liquidation_value": balances.get("liquidationValue"),
            "cash_balance": balances.get("cashBalance"),
            "available_funds": balances.get("availableFunds"),
            "buying_power": balances.get("buyingPower"),
            "long_market_value": balances.get("longMarketValue"),
            "short_market_value": balances.get("shortMarketValue"),
            "long_option_market_value": balances.get("longOptionMarketValue"),
            "short_option_market_value": balances.get("shortOptionMarketValue"),
            "money_market_fund": balances.get("moneyMarketFund"),
            "maintenance_requirement": balances.get("maintenanceRequirement"),
            "is_day_trader": acct.get("isDayTrader"),
            "is_portfolio_margin": acct.get("isPortfolioMargin"),
        })
    return pd.DataFrame(rows, columns=[
        "snapshot_date", "source_row", "account_tail", "account_type", "liquidation_value",
        "cash_balance", "available_funds", "buying_power", "long_market_value",
        "short_market_value", "long_option_market_value", "short_option_market_value",
        "money_market_fund", "maintenance_requirement", "is_day_trader", "is_portfolio_margin",
    ])


def flatten_positions(accounts_payload, snapshot_date):
    rows = []
    for account in accounts_payload if isinstance(accounts_payload, list) else []:
        acct = account.get("securitiesAccount") or {}
        tail = account_tail(acct)
        for idx, position in enumerate(acct.get("positions") or [], start=1):
            instrument = position.get("instrument") or {}
            asset_type = instrument.get("assetType")
            underlying = instrument.get("underlyingSymbol") or instrument.get("symbol")
            expiration, strike = parse_option_fields(instrument)
            qty_long = position.get("longQuantity") or 0
            qty_short = position.get("shortQuantity") or 0
            rows.append({
                "snapshot_date": snapshot_date,
                "account_tail": tail,
                "source_row": idx,
                "symbol": instrument.get("symbol"),
                "uniform_symbol": instrument.get("uniformSymbol"),
                "underlying": underlying,
                "description": instrument.get("description"),
                "asset_type": asset_type,
                "instrument_type": instrument.get("type"),
                "put_call": instrument.get("putCall"),
                "option_expiration": expiration,
                "option_strike": strike,
                "long_quantity": qty_long,
                "short_quantity": qty_short,
                "net_quantity": qty_long - qty_short,
                "average_price": position.get("averagePrice"),
                "average_long_price": position.get("averageLongPrice"),
                "market_value": position.get("marketValue"),
                "current_day_profit_loss": position.get("currentDayProfitLoss"),
                "current_day_profit_loss_pct": position.get("currentDayProfitLossPercentage"),
                "long_open_profit_loss": position.get("longOpenProfitLoss"),
                "maintenance_requirement": position.get("maintenanceRequirement"),
            })
    return pd.DataFrame(rows, columns=[
        "snapshot_date", "account_tail", "source_row", "symbol", "uniform_symbol", "underlying",
        "description", "asset_type", "instrument_type", "put_call", "option_expiration",
        "option_strike", "long_quantity", "short_quantity", "net_quantity", "average_price",
        "average_long_price", "market_value", "current_day_profit_loss",
        "current_day_profit_loss_pct", "long_open_profit_loss", "maintenance_requirement",
    ])


def reconcile_position_day_pnl(positions_df, quotes_df):
    """Fix corrupt per-position ``currentDayProfitLoss`` values.

    Schwab's position ``currentDayProfitLoss`` is occasionally wrong for
    box-spread / cash-like ETFs (e.g. BOXX returned $5,873.46 on a day the
    underlying quote only moved $0.02, implying a nonsensical ~34% daily move).
    For any non-option position that has a live quote, ``net_quantity ×
    quote.net_change`` is the definitional day P&L from the same API and is the
    trustworthy value, so we prefer it. The raw API field and the chosen source
    are preserved as audit columns.
    """
    if positions_df.empty:
        for col in ("day_pnl_api", "day_pnl_quote", "day_pnl_source"):
            positions_df[col] = pd.Series(dtype="object")
        return positions_df

    net_change_by_symbol = {}
    if not quotes_df.empty:
        for _, q in quotes_df.iterrows():
            nc = q.get("net_change")
            if nc is not None and pd.notna(nc):
                net_change_by_symbol[q.get("symbol")] = float(nc)

    api_values, quote_values, sources, reconciled = [], [], [], []
    for _, pos in positions_df.iterrows():
        api_val = pos.get("current_day_profit_loss")
        api_val = float(api_val) if api_val is not None and pd.notna(api_val) else None
        net_qty = pos.get("net_quantity")
        net_qty = float(net_qty) if net_qty is not None and pd.notna(net_qty) else 0.0
        symbol = pos.get("symbol")
        net_change = net_change_by_symbol.get(symbol)

        quote_val = net_qty * net_change if (net_change is not None and pos.get("asset_type") != "OPTION") else None
        if quote_val is not None:
            chosen, source = quote_val, "quote_net_change"
        elif api_val is not None:
            chosen, source = api_val, "api_current_day_pnl"
        else:
            chosen, source = None, "unavailable"

        api_values.append(api_val)
        quote_values.append(quote_val)
        sources.append(source)
        reconciled.append(chosen)

    positions_df = positions_df.copy()
    positions_df["day_pnl_api"] = api_values
    positions_df["day_pnl_quote"] = quote_values
    positions_df["day_pnl_source"] = sources
    positions_df["current_day_profit_loss"] = reconciled
    return positions_df


def flatten_quotes(quotes_payload, snapshot_date):
    rows = []
    if not isinstance(quotes_payload, dict):
        return pd.DataFrame(rows, columns=[
            "snapshot_date", "symbol", "asset_main_type", "asset_sub_type", "description",
            "exchange", "last_price", "mark", "bid_price", "ask_price", "net_change",
            "net_percent_change", "total_volume", "quote_time", "pe_ratio", "div_yield",
            "eps", "is_shortable", "optionable",
        ])
    for symbol, payload in quotes_payload.items():
        quote = payload.get("quote") or {}
        regular = payload.get("regular") or {}
        reference = payload.get("reference") or {}
        fundamental = payload.get("fundamental") or {}
        rows.append({
            "snapshot_date": snapshot_date,
            "symbol": symbol,
            "asset_main_type": payload.get("assetMainType"),
            "asset_sub_type": payload.get("assetSubType"),
            "description": reference.get("description"),
            "exchange": reference.get("exchange"),
            "last_price": quote.get("lastPrice") or regular.get("regularMarketLastPrice"),
            "mark": quote.get("mark"),
            "bid_price": quote.get("bidPrice"),
            "ask_price": quote.get("askPrice"),
            "net_change": quote.get("netChange") or regular.get("regularMarketNetChange"),
            "net_percent_change": quote.get("netPercentChange") or regular.get("regularMarketPercentChange"),
            "total_volume": quote.get("totalVolume"),
            "quote_time": quote.get("quoteTime") or regular.get("regularMarketTradeTime"),
            "pe_ratio": fundamental.get("peRatio"),
            "div_yield": fundamental.get("divYield"),
            "eps": fundamental.get("eps"),
            "is_shortable": reference.get("isShortable"),
            "optionable": reference.get("optionable"),
        })
    return pd.DataFrame(rows, columns=[
        "snapshot_date", "symbol", "asset_main_type", "asset_sub_type", "description",
        "exchange", "last_price", "mark", "bid_price", "ask_price", "net_change",
        "net_percent_change", "total_volume", "quote_time", "pe_ratio", "div_yield",
        "eps", "is_shortable", "optionable",
    ])


def iso_date(value):
    """Normalize Schwab date fields (e.g. '2026-08-11T00:00:00Z') to 'YYYY-MM-DD'."""
    if not value:
        return None
    text = str(value)
    return text[:10] if len(text) >= 10 else None


def build_portfolio_events(quotes_payload, positions_df, snapshot_date, earnings_by_symbol=None):
    """Build a unified upcoming-events table for held symbols.

    Dividend ex/pay dates come straight from the Schwab `fundamental` block.
    Next-earnings dates are optional: Schwab only exposes `lastEarningsDate`, so
    a confirmed next date must come from `earnings_by_symbol` (an external
    calendar). When absent we still record `last_earnings` for context.
    """
    earnings_by_symbol = earnings_by_symbol or {}
    held = set()
    if not positions_df.empty:
        held.update(positions_df["symbol"].dropna().tolist())
        held.update(positions_df["underlying"].dropna().tolist())

    rows = []

    def add(symbol, event_type, event_date, detail):
        if not event_date:
            return
        rows.append({
            "snapshot_date": snapshot_date,
            "symbol": symbol,
            "event_type": event_type,
            "event_date": event_date,
            "detail": detail,
        })

    if isinstance(quotes_payload, dict):
        for symbol, payload in quotes_payload.items():
            if held and symbol not in held:
                continue
            fund = payload.get("fundamental") or {}
            div_amt = fund.get("divAmount") or 0
            add(symbol, "dividend_ex", iso_date(fund.get("nextDivExDate")),
                f"Ex-dividend · ${div_amt}/sh" if div_amt else "Ex-dividend")
            add(symbol, "dividend_pay", iso_date(fund.get("nextDivPayDate")),
                f"Dividend pay · ${div_amt}/sh" if div_amt else "Dividend pay")
            # Prefer an external confirmed next-earnings date; fall back to none.
            next_earn = earnings_by_symbol.get(symbol)
            if next_earn:
                add(symbol, "earnings", iso_date(next_earn.get("date")),
                    next_earn.get("detail") or "Earnings")

    events_df = pd.DataFrame(rows, columns=[
        "snapshot_date", "symbol", "event_type", "event_date", "detail",
    ])
    if not events_df.empty:
        events_df = events_df.sort_values(["event_date", "symbol"]).reset_index(drop=True)
    return events_df


def _load_env_key(*names):
    """Read the first available key from the vault .env (best-effort, no deps)."""
    import os
    for name in names:
        if os.environ.get(name):
            return os.environ[name]
    env_path = HISTORY_ROOT.parents[2] / ".env"  # vault root /.env
    if not env_path.exists():
        return None
    try:
        for line in env_path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, value = line.partition("=")
            if key.strip() in names:
                return value.strip().strip('"').strip("'")
    except OSError:
        return None
    return None


def fetch_next_earnings(symbols):
    """Resolve next earnings date per equity symbol from Alpha Vantage.

    One bulk call returns the entire forward US earnings calendar (CSV); we
    filter locally to the held tickers and pick the earliest upcoming date. This
    keeps us to a single request/day, well under the free tier's 25/day limit.

    Key from vault .env as ALPHAVANTAGE_API_KEY (or ALPHA_VANTAGE_API_KEY); falls
    back to the public `demo` key, which works for this endpoint. Dates are
    analyst-estimated (no free API flags exchange-confirmed), so the viewer
    labels them as estimates. Degrades to {} on any error.
    """
    if not symbols:
        return {}
    api_key = _load_env_key("ALPHAVANTAGE_API_KEY", "ALPHA_VANTAGE_API_KEY") or "demo"
    wanted = set(symbols)
    today = datetime.now().date().isoformat()
    out = {}
    try:
        resp = httpx.get(
            "https://www.alphavantage.co/query",
            params={"function": "EARNINGS_CALENDAR", "horizon": "3month", "apikey": api_key},
            timeout=30,
        )
        if resp.status_code != httpx.codes.OK:
            print(f"earnings: Alpha Vantage HTTP {resp.status_code} — skipping earnings")
            return {}
        import csv
        import io
        text = resp.text or ""
        if not text.lstrip().lower().startswith("symbol"):
            # AV returns a JSON note (not CSV) when rate-limited or key is bad.
            print("earnings: Alpha Vantage returned no CSV (rate-limited or bad key) — skipping earnings")
            return {}
        reader = csv.DictReader(io.StringIO(text))
        for row in reader:
            symbol = (row.get("symbol") or "").strip()
            report_date = (row.get("reportDate") or "").strip()
            if symbol not in wanted or not report_date or report_date < today:
                continue
            # Keep the earliest upcoming report per symbol.
            if symbol in out and out[symbol]["date"] <= report_date:
                continue
            when = (row.get("timeOfTheDay") or "").strip()
            estimate = (row.get("estimate") or "").strip()
            detail = "Earnings (est.)"
            if estimate:
                detail += f" · EPS est {estimate}"
            if when:
                detail += f" · {when}"
            out[symbol] = {"date": report_date, "detail": detail}
    except Exception as exc:
        print(f"earnings: Alpha Vantage fetch failed ({type(exc).__name__}) — skipping earnings")
        return {}
    print(f"earnings: resolved next dates for {len(out)}/{len(symbols)} equities via Alpha Vantage")
    return out


def status_row(snapshot_date, source, status, rows=0, detail=""):
    return {
        "snapshot_date": snapshot_date,
        "source": source,
        "status": status,
        "rows": rows,
        "detail": detail,
    }


def source_status_df(rows):
    return pd.DataFrame(rows, columns=["snapshot_date", "source", "status", "rows", "detail"])


def equity_symbols_from_positions(positions_df, limit=None):
    if positions_df.empty:
        return []
    symbols = sorted(set(
        positions_df[positions_df["asset_type"] == "EQUITY"]["symbol"].dropna().tolist()
    ))
    return symbols[:limit] if limit else symbols


def top_equity_symbols_by_value(positions_df, limit=12):
    if positions_df.empty:
        return []
    df = positions_df[positions_df["asset_type"] == "EQUITY"].copy()
    if df.empty:
        return []
    df["abs_market_value"] = df["market_value"].abs()
    return df.sort_values("abs_market_value", ascending=False)["symbol"].dropna().head(limit).tolist()


def fetch_sec_filings(symbols, snapshot_date):
    """Fetch recent SEC filing metadata for held equities.

    Uses the official no-key EDGAR JSON endpoints. SEC asks automated clients
    to identify themselves with a User-Agent; users can override it via
    SEC_USER_AGENT in .env.
    """
    columns = [
        "snapshot_date", "symbol", "cik", "company_name", "form", "filing_date",
        "report_date", "accession_number", "primary_document", "description",
    ]
    if not symbols:
        return pd.DataFrame(columns=columns), status_row(snapshot_date, "SEC EDGAR", "skipped", 0, "no equity symbols")
    user_agent = _load_env_key("SEC_USER_AGENT") or "CharlieSchwabDashboard/1.0 local-personal-use"
    headers = {"User-Agent": user_agent, "Accept": "application/json", "Accept-Encoding": "gzip, deflate"}
    data_headers = {"User-Agent": user_agent, "Accept": "application/json", "Accept-Encoding": "gzip, deflate"}
    wanted = {s.upper() for s in symbols}
    rows = []
    ticker_source = "official ticker map"
    try:
        ticker_resp = httpx.get("https://www.sec.gov/files/company_tickers.json", headers=headers, timeout=30)
        if ticker_resp.status_code == httpx.codes.OK and "json" in (ticker_resp.headers.get("content-type") or ""):
            tickers = ticker_resp.json()
            by_symbol = {
                item.get("ticker", "").upper(): item
                for item in (tickers.values() if isinstance(tickers, dict) else [])
            }
        else:
            by_symbol = SEC_CIK_FALLBACK
            ticker_source = "local CIK fallback"
        for symbol in sorted(wanted):
            item = by_symbol.get(symbol)
            if not item:
                continue
            cik = str(item.get("cik_str")).zfill(10)
            resp = httpx.get(f"https://data.sec.gov/submissions/CIK{cik}.json", headers=data_headers, timeout=30)
            if resp.status_code != httpx.codes.OK:
                continue
            recent = (resp.json().get("filings") or {}).get("recent") or {}
            forms = recent.get("form") or []
            filing_dates = recent.get("filingDate") or []
            report_dates = recent.get("reportDate") or []
            accessions = recent.get("accessionNumber") or []
            docs = recent.get("primaryDocument") or []
            descriptions = recent.get("primaryDocDescription") or []
            kept = 0
            for idx, form in enumerate(forms):
                if form not in {"10-K", "10-Q", "8-K", "6-K", "20-F"}:
                    continue
                rows.append({
                    "snapshot_date": snapshot_date,
                    "symbol": symbol,
                    "cik": cik,
                    "company_name": item.get("title"),
                    "form": form,
                    "filing_date": filing_dates[idx] if idx < len(filing_dates) else "",
                    "report_date": report_dates[idx] if idx < len(report_dates) else "",
                    "accession_number": accessions[idx] if idx < len(accessions) else "",
                    "primary_document": docs[idx] if idx < len(docs) else "",
                    "description": descriptions[idx] if idx < len(descriptions) else "",
                })
                kept += 1
                if kept >= 5:
                    break
            time.sleep(0.12)
        df = pd.DataFrame(rows, columns=columns)
        return df, status_row(snapshot_date, "SEC EDGAR", "ok" if len(df) else "partial", len(df), f"{len(wanted)} symbols checked via {ticker_source}")
    except Exception as exc:
        return pd.DataFrame(columns=columns), status_row(snapshot_date, "SEC EDGAR", "error", 0, type(exc).__name__)


def fetch_fred_macro_events(snapshot_date, months=6):
    columns = ["snapshot_date", "event_type", "event_date", "source", "detail", "importance"]
    rows = []
    start = datetime.fromisoformat(snapshot_date).date()
    end = start + timedelta(days=31 * months)

    # FOMC dates are not a FRED release series; keep a small local calendar.
    fomc_dates = [
        "2026-01-27", "2026-01-28", "2026-03-17", "2026-03-18",
        "2026-04-28", "2026-04-29", "2026-06-16", "2026-06-17",
        "2026-07-28", "2026-07-29", "2026-09-15", "2026-09-16",
        "2026-10-27", "2026-10-28", "2026-12-08", "2026-12-09",
    ]
    for d in fomc_dates:
        if start.isoformat() <= d <= end.isoformat():
            rows.append({
                "snapshot_date": snapshot_date,
                "event_type": "fomc",
                "event_date": d,
                "source": "Federal Reserve",
                "detail": "FOMC scheduled meeting",
                "importance": "high",
            })

    api_key = _load_env_key("FRED_API_KEY")
    if not api_key:
        df = pd.DataFrame(rows, columns=columns)
        return df, status_row(snapshot_date, "FRED", "partial", len(df), "API key missing; local FOMC calendar only")
    wanted = ("Consumer Price Index", "Employment Situation", "Gross Domestic Product", "Personal Income and Outlays", "Producer Price Index")
    try:
        resp = httpx.get(
            "https://api.stlouisfed.org/fred/releases/dates",
            params={
                "api_key": api_key,
                "file_type": "json",
                "realtime_start": start.isoformat(),
                "realtime_end": end.isoformat(),
                "include_release_dates_with_no_data": "true",
                "limit": 1000,
            },
            timeout=30,
        )
        if resp.status_code != httpx.codes.OK:
            df = pd.DataFrame(rows, columns=columns)
            return df, status_row(snapshot_date, "FRED", "partial", len(df), f"HTTP {resp.status_code}; FOMC only")
        for item in resp.json().get("release_dates") or []:
            name = item.get("release_name") or ""
            if not any(key in name for key in wanted):
                continue
            rows.append({
                "snapshot_date": snapshot_date,
                "event_type": "macro",
                "event_date": item.get("date"),
                "source": "FRED",
                "detail": name,
                "importance": "high",
            })
        df = pd.DataFrame(rows, columns=columns).drop_duplicates()
        return df, status_row(snapshot_date, "FRED", "ok", len(df), "macro release dates + FOMC")
    except Exception as exc:
        df = pd.DataFrame(rows, columns=columns)
        return df, status_row(snapshot_date, "FRED", "partial", len(df), f"{type(exc).__name__}; FOMC only")


def fetch_coingecko_crypto(snapshot_date, positions_df):
    columns = ["snapshot_date", "asset", "price_usd", "market_cap_usd", "change_24h_pct", "source", "detail"]
    held = set(positions_df["symbol"].dropna().tolist()) if not positions_df.empty else set()
    if not {"IBIT", "BTCO"} & held:
        return pd.DataFrame(columns=columns), status_row(snapshot_date, "CoinGecko", "skipped", 0, "no BTC ETF positions")
    headers = {}
    key = _load_env_key("COINGECKO_API_KEY", "CG_DEMO_API_KEY")
    if key:
        headers["x-cg-demo-api-key"] = key
    try:
        resp = httpx.get(
            "https://api.coingecko.com/api/v3/simple/price",
            params={
                "ids": "bitcoin",
                "vs_currencies": "usd",
                "include_market_cap": "true",
                "include_24hr_change": "true",
            },
            headers=headers,
            timeout=30,
        )
        if resp.status_code != httpx.codes.OK:
            return pd.DataFrame(columns=columns), status_row(snapshot_date, "CoinGecko", "error", 0, f"HTTP {resp.status_code}")
        btc = (resp.json() or {}).get("bitcoin") or {}
        row = {
            "snapshot_date": snapshot_date,
            "asset": "bitcoin",
            "price_usd": btc.get("usd"),
            "market_cap_usd": btc.get("usd_market_cap"),
            "change_24h_pct": btc.get("usd_24h_change"),
            "source": "CoinGecko",
            "detail": "BTC reference for IBIT/BTCO",
        }
        return pd.DataFrame([row], columns=columns), status_row(snapshot_date, "CoinGecko", "ok", 1, "BTC simple price")
    except Exception as exc:
        return pd.DataFrame(columns=columns), status_row(snapshot_date, "CoinGecko", "error", 0, type(exc).__name__)


def fetch_finnhub(symbols, snapshot_date):
    rating_cols = ["snapshot_date", "symbol", "period", "strong_buy", "buy", "hold", "sell", "strong_sell", "source"]
    news_cols = ["snapshot_date", "symbol", "datetime", "headline", "source", "url"]
    key = _load_env_key("FINNHUB_API_KEY")
    if not key:
        return (
            pd.DataFrame(columns=rating_cols),
            pd.DataFrame(columns=news_cols),
            status_row(snapshot_date, "Finnhub", "skipped", 0, "API key missing"),
        )
    ratings = []
    news = []
    end = datetime.fromisoformat(snapshot_date).date()
    start = end - timedelta(days=14)
    try:
        for symbol in symbols[:10]:
            rec = httpx.get(
                "https://finnhub.io/api/v1/stock/recommendation",
                params={"symbol": symbol, "token": key},
                timeout=20,
            )
            if rec.status_code == httpx.codes.OK:
                items = rec.json() or []
                if items:
                    item = items[0]
                    ratings.append({
                        "snapshot_date": snapshot_date,
                        "symbol": symbol,
                        "period": item.get("period"),
                        "strong_buy": item.get("strongBuy"),
                        "buy": item.get("buy"),
                        "hold": item.get("hold"),
                        "sell": item.get("sell"),
                        "strong_sell": item.get("strongSell"),
                        "source": "Finnhub",
                    })
            headlines = httpx.get(
                "https://finnhub.io/api/v1/company-news",
                params={"symbol": symbol, "from": start.isoformat(), "to": end.isoformat(), "token": key},
                timeout=20,
            )
            if headlines.status_code == httpx.codes.OK:
                for item in (headlines.json() or [])[:3]:
                    ts = item.get("datetime")
                    when = datetime.fromtimestamp(ts).isoformat() if ts else ""
                    news.append({
                        "snapshot_date": snapshot_date,
                        "symbol": symbol,
                        "datetime": when,
                        "headline": item.get("headline"),
                        "source": item.get("source"),
                        "url": item.get("url"),
                    })
            time.sleep(0.2)
        return (
            pd.DataFrame(ratings, columns=rating_cols),
            pd.DataFrame(news, columns=news_cols),
            status_row(snapshot_date, "Finnhub", "ok", len(ratings) + len(news), f"{len(symbols[:10])} symbols checked"),
        )
    except Exception as exc:
        return (
            pd.DataFrame(ratings, columns=rating_cols),
            pd.DataFrame(news, columns=news_cols),
            status_row(snapshot_date, "Finnhub", "partial" if ratings or news else "error", len(ratings) + len(news), type(exc).__name__),
        )


def flatten_price_history(price_payload_by_symbol):
    rows = []
    for symbol, payload in price_payload_by_symbol.items():
        for candle in payload.get("candles") or []:
            millis = candle.get("datetime")
            candle_date = datetime.fromtimestamp(millis / 1000).date().isoformat() if millis else None
            rows.append({
                "symbol": symbol,
                "date": candle_date,
                "open": candle.get("open"),
                "high": candle.get("high"),
                "low": candle.get("low"),
                "close": candle.get("close"),
                "volume": candle.get("volume"),
                "source": "schwab_trader_api",
            })
    return pd.DataFrame(rows, columns=["symbol", "date", "open", "high", "low", "close", "volume", "source"])


def flatten_transactions(transaction_payload_by_account):
    rows = []
    for acct_tail, transactions in transaction_payload_by_account.items():
        for idx, tx in enumerate(transactions if isinstance(transactions, list) else [], start=1):
            item = tx.get("transferItems", [{}])[0] if tx.get("transferItems") else {}
            instrument = item.get("instrument") or {}
            rows.append({
                "account_tail": acct_tail,
                "source_row": idx,
                "activity_id_tail": mask_tail(str(tx.get("activityId"))) if tx.get("activityId") else "",
                "time": tx.get("time"),
                "trade_date": tx.get("tradeDate"),
                "settlement_date": tx.get("settlementDate"),
                "type": tx.get("type"),
                "status": tx.get("status"),
                "description": tx.get("description"),
                "net_amount": tx.get("netAmount"),
                "symbol": instrument.get("symbol"),
                "asset_type": instrument.get("assetType"),
                "quantity": item.get("amount"),
                "price": item.get("price"),
                "cost": item.get("cost"),
            })
    return pd.DataFrame(rows, columns=[
        "account_tail", "source_row", "activity_id_tail", "time", "trade_date",
        "settlement_date", "type", "status", "description", "net_amount", "symbol",
        "asset_type", "quantity", "price", "cost",
    ])


def flatten_option_chains(option_chain_payloads, snapshot_date):
    rows = []
    for underlying, payload in option_chain_payloads.items():
        if not isinstance(payload, dict) or payload.get("error"):
            continue
        underlying_quote = payload.get("underlying") or {}
        underlying_price = payload.get("underlyingPrice") or underlying_quote.get("mark") or underlying_quote.get("last")
        for map_name, fallback_type in [("callExpDateMap", "CALL"), ("putExpDateMap", "PUT")]:
            for expiration_key, strikes in (payload.get(map_name) or {}).items():
                expiration = expiration_key.split(":", 1)[0]
                for strike_key, contracts in (strikes or {}).items():
                    for contract in contracts or []:
                        rows.append({
                            "snapshot_date": snapshot_date,
                            "underlying": underlying,
                            "underlying_price": underlying_price,
                            "put_call": contract.get("putCall") or fallback_type,
                            "contract_symbol": contract.get("symbol"),
                            "description": contract.get("description"),
                            "expiration": expiration,
                            "days_to_expiration": contract.get("daysToExpiration"),
                            "strike": contract.get("strikePrice") or float(strike_key),
                            "bid": contract.get("bid"),
                            "ask": contract.get("ask"),
                            "last": contract.get("last"),
                            "mark": contract.get("mark"),
                            "volume": contract.get("totalVolume"),
                            "open_interest": contract.get("openInterest"),
                            "volatility": contract.get("volatility"),
                            "delta": contract.get("delta"),
                            "gamma": contract.get("gamma"),
                            "theta": contract.get("theta"),
                            "vega": contract.get("vega"),
                            "rho": contract.get("rho"),
                            "intrinsic_value": contract.get("intrinsicValue"),
                            "extrinsic_value": contract.get("extrinsicValue"),
                            "break_even": contract.get("breakEven"),
                            "in_the_money": contract.get("inTheMoney"),
                        })
    return pd.DataFrame(rows, columns=[
        "snapshot_date", "underlying", "underlying_price", "put_call", "contract_symbol",
        "description", "expiration", "days_to_expiration", "strike", "bid", "ask",
        "last", "mark", "volume", "open_interest", "volatility", "delta", "gamma",
        "theta", "vega", "rho", "intrinsic_value", "extrinsic_value", "break_even",
        "in_the_money",
    ])


def build_option_position_risk(positions_df, option_chains_df, snapshot_date):
    rows = []
    option_positions = positions_df[positions_df["asset_type"] == "OPTION"].copy() if not positions_df.empty else pd.DataFrame()
    for _, pos in option_positions.iterrows():
        match = pd.DataFrame()
        if not option_chains_df.empty:
            match = option_chains_df[
                (option_chains_df["underlying"] == pos["underlying"]) &
                (option_chains_df["put_call"] == pos["put_call"]) &
                (option_chains_df["expiration"] == pos["option_expiration"]) &
                (option_chains_df["strike"].astype(float) == float(pos["option_strike"] or 0))
            ]
        chain = match.iloc[0].to_dict() if len(match) else {}
        short_qty = float(pos.get("short_quantity") or 0)
        long_qty = float(pos.get("long_quantity") or 0)
        # Signed net contracts: a short call/put must count as negative exposure so
        # delta dollars point the right way. Using `short_qty or long_qty` (the old
        # code) treated shorts as positive and inverted the directional sign.
        net_contracts = long_qty - short_qty
        strike = float(pos.get("option_strike") or 0)
        underlying_price = float(chain.get("underlying_price") or 0)
        delta = chain.get("delta")
        rows.append({
            "snapshot_date": snapshot_date,
            "symbol": pos.get("symbol"),
            "underlying": pos.get("underlying"),
            "put_call": pos.get("put_call"),
            "expiration": pos.get("option_expiration"),
            "strike": strike,
            "short_quantity": short_qty,
            "long_quantity": long_qty,
            "net_contracts": net_contracts,
            "market_value": pos.get("market_value"),
            "notional": abs(net_contracts * strike * 100),
            "days_to_expiration": chain.get("days_to_expiration"),
            "delta": delta,
            "theta": chain.get("theta"),
            "vega": chain.get("vega"),
            "iv": chain.get("volatility"),
            "open_interest": chain.get("open_interest"),
            "assignment_notional": abs(short_qty * strike * 100),
            "delta_dollars": (delta or 0) * net_contracts * 100 * underlying_price,
        })
    return pd.DataFrame(rows, columns=[
        "snapshot_date", "symbol", "underlying", "put_call", "expiration", "strike",
        "short_quantity", "long_quantity", "net_contracts", "market_value", "notional",
        "days_to_expiration", "delta", "theta", "vega", "iv", "open_interest",
        "assignment_notional", "delta_dollars",
    ])


def write_viewer_data(path, snapshot_date, tables):
    lines = [
        f"window.SCHWAB_DATA_META = {json.dumps({'date': snapshot_date, 'source': 'schwab_trader_api'}, ensure_ascii=False)};",
    ]
    for name, df in tables.items():
        lines.append(f"window.{name} = {json.dumps(df.to_csv(index=False), ensure_ascii=False)};")
    lines.append("")
    Path(path).write_text("\n".join(lines), encoding="utf-8")


def latest_by_name(paths):
    items = sorted(paths)
    return items[-1] if items else None


def fetch_symbols_from_positions(positions_df):
    if positions_df.empty:
        return ["SPY", "QQQ"]
    symbols = positions_df[
        positions_df["asset_type"].isin(["EQUITY", "COLLECTIVE_INVESTMENT", "ETF"])
    ]["symbol"].dropna().tolist()
    underlyings = positions_df[positions_df["asset_type"] == "OPTION"]["underlying"].dropna().tolist()
    return sorted(set(symbols + underlyings + ["SPY", "QQQ"]))


def main():
    args = parse_args()
    creds = load_credentials()
    path = token_path(args.token_path)
    if not path.exists():
        raise SystemExit(f"Token file not found: {path}. Run `mise run auth` first.")

    client = client_from_token_file(
        str(path),
        api_key=creds.client_id,
        app_secret=creds.client_secret,
        enforce_enums=False,
    )

    root = Path(args.out_dir)
    processed = root / "processed"
    db_dir = root / "db"
    processed.mkdir(parents=True, exist_ok=True)
    db_dir.mkdir(parents=True, exist_ok=True)

    account_numbers = ok_json(client.get_account_numbers())
    accounts = ok_json(client.get_accounts(fields=[Client.Account.Fields.POSITIONS]))
    accounts_df = flatten_accounts(accounts, args.date)
    positions_df = flatten_positions(accounts, args.date)

    symbols = fetch_symbols_from_positions(positions_df)
    quotes = ok_json(client.get_quotes(symbols))
    quotes_df = flatten_quotes(quotes, args.date)
    positions_df = reconcile_position_day_pnl(positions_df, quotes_df)

    end_dt = datetime.combine(datetime.fromisoformat(args.date).date(), datetime.min.time())
    start_dt = end_dt - timedelta(days=args.price_history_days)
    price_payloads = {}
    price_errors = []
    for symbol in symbols:
        try:
            price_payloads[symbol] = ok_json(client.get_price_history_every_day(symbol, start_datetime=start_dt, end_datetime=end_dt))
        except Exception as exc:
            price_errors.append({"symbol": symbol, "error": type(exc).__name__})
    price_df = flatten_price_history(price_payloads)
    price_errors_df = pd.DataFrame(price_errors, columns=["symbol", "error"])

    tx_start = end_dt - timedelta(days=args.lookback_days)
    transactions_by_account = {}
    for row in account_numbers if isinstance(account_numbers, list) else []:
        acct_hash = row.get("hashValue")
        acct_tail = mask_tail(str(row.get("accountNumber"))) if row.get("accountNumber") else ""
        if not acct_hash:
            continue
        transactions_by_account[acct_tail] = ok_json(client.get_transactions(acct_hash, start_date=tx_start, end_date=end_dt))
    transactions_df = flatten_transactions(transactions_by_account)

    option_chain_payloads = {}
    if not args.skip_option_chains and not positions_df.empty:
        option_positions = positions_df[positions_df["asset_type"] == "OPTION"]
        option_underlyings = sorted(set(option_positions["underlying"].dropna().tolist()))
        for symbol in option_underlyings:
            # The old default (strike_count=4) only returned the 4 strikes nearest
            # the money, so any held option that was further ITM/OTM never matched
            # its chain row and lost its Greeks/DTE. Request the full strike range,
            # bounded to the expirations we actually hold so the payload stays small.
            held = option_positions[option_positions["underlying"] == symbol]
            expirations = sorted({e for e in held["option_expiration"].dropna().tolist() if e})
            kwargs = {"strike_range": "ALL", "include_underlying_quote": True}
            if expirations:
                try:
                    kwargs["from_date"] = datetime.fromisoformat(expirations[0]).date()
                    kwargs["to_date"] = datetime.fromisoformat(expirations[-1]).date()
                except ValueError:
                    pass
            try:
                option_chain_payloads[symbol] = ok_json(client.get_option_chain(symbol, **kwargs))
            except Exception as exc:
                # Fall back to a wide near-the-money window if the full-range query
                # is rejected, so we still capture most held strikes.
                try:
                    option_chain_payloads[symbol] = ok_json(client.get_option_chain(symbol, strike_count=50, include_underlying_quote=True))
                except Exception:
                    option_chain_payloads[symbol] = {"error": type(exc).__name__}
    option_chains_df = flatten_option_chains(option_chain_payloads, args.date)
    option_risk_df = build_option_position_risk(positions_df, option_chains_df, args.date)

    earnings_by_symbol = {}
    if not args.skip_earnings:
        equity_symbols = sorted(set(
            positions_df[positions_df["asset_type"] == "EQUITY"]["symbol"].dropna().tolist()
        )) if not positions_df.empty else []
        earnings_by_symbol = fetch_next_earnings(equity_symbols)
    events_df = build_portfolio_events(quotes, positions_df, args.date, earnings_by_symbol)

    source_status_rows = [
        status_row(args.date, "Schwab Trader API", "ok", len(accounts_df) + len(positions_df) + len(quotes_df), "accounts, positions, quotes, prices, transactions"),
        status_row(args.date, "Alpha Vantage", "skipped" if args.skip_earnings else "ok", len(earnings_by_symbol), "earnings calendar"),
    ]
    equity_symbols = equity_symbols_from_positions(positions_df)
    top_symbols = top_equity_symbols_by_value(positions_df)

    if args.skip_sec:
        sec_filings_df = pd.DataFrame(columns=[
            "snapshot_date", "symbol", "cik", "company_name", "form", "filing_date",
            "report_date", "accession_number", "primary_document", "description",
        ])
        source_status_rows.append(status_row(args.date, "SEC EDGAR", "skipped", 0, "--skip-sec"))
    else:
        sec_filings_df, sec_status = fetch_sec_filings(equity_symbols, args.date)
        source_status_rows.append(sec_status)

    if args.skip_fred:
        macro_events_df = pd.DataFrame(columns=["snapshot_date", "event_type", "event_date", "source", "detail", "importance"])
        source_status_rows.append(status_row(args.date, "FRED", "skipped", 0, "--skip-fred"))
    else:
        macro_events_df, fred_status = fetch_fred_macro_events(args.date)
        source_status_rows.append(fred_status)

    if args.skip_coingecko:
        crypto_prices_df = pd.DataFrame(columns=["snapshot_date", "asset", "price_usd", "market_cap_usd", "change_24h_pct", "source", "detail"])
        source_status_rows.append(status_row(args.date, "CoinGecko", "skipped", 0, "--skip-coingecko"))
    else:
        crypto_prices_df, cg_status = fetch_coingecko_crypto(args.date, positions_df)
        source_status_rows.append(cg_status)

    if args.skip_finnhub:
        analyst_ratings_df = pd.DataFrame(columns=["snapshot_date", "symbol", "period", "strong_buy", "buy", "hold", "sell", "strong_sell", "source"])
        news_headlines_df = pd.DataFrame(columns=["snapshot_date", "symbol", "datetime", "headline", "source", "url"])
        source_status_rows.append(status_row(args.date, "Finnhub", "skipped", 0, "--skip-finnhub"))
    else:
        analyst_ratings_df, news_headlines_df, finnhub_status = fetch_finnhub(top_symbols, args.date)
        source_status_rows.append(finnhub_status)
    source_status = source_status_df(source_status_rows)

    raw_path = processed / f"schwab-api-raw-sanitized-{args.date}.json"
    raw_path.write_text(
        json.dumps(
            sanitize_api_payload({
                "captured_at": datetime.now().isoformat(timespec="seconds"),
                "account_numbers": account_numbers,
                "accounts": accounts,
                "quotes": quotes,
                "price_history": price_payloads,
                "price_errors": price_errors,
                "recent_transactions": transactions_by_account,
                "option_chains": option_chain_payloads,
                "external_source_status": source_status.to_dict(orient="records"),
            }),
            indent=2,
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )

    db_path = db_dir / f"schwab-api-{args.date}.duckdb"
    if db_path.exists():
        db_path.unlink()
    con = duckdb.connect(str(db_path))
    for table_name, df in [
        ("account_snapshots", accounts_df),
        ("position_snapshots", positions_df),
        ("market_quotes", quotes_df),
        ("market_prices_daily", price_df),
        ("market_price_errors", price_errors_df),
        ("recent_transactions_api", transactions_df),
        ("option_chains", option_chains_df),
        ("option_position_risk", option_risk_df),
        ("portfolio_events", events_df),
        ("source_status", source_status),
        ("sec_filings", sec_filings_df),
        ("macro_events", macro_events_df),
        ("crypto_prices", crypto_prices_df),
        ("analyst_ratings", analyst_ratings_df),
        ("news_headlines", news_headlines_df),
    ]:
        con.register("df", df)
        con.execute(f"create table {table_name} as select * from df")
        con.unregister("df")
    con.close()

    viewer_tables = {
        "SCHWAB_API_ACCOUNTS_CSV": accounts_df,
        "SCHWAB_API_POSITIONS_CSV": positions_df,
        "SCHWAB_API_QUOTES_CSV": quotes_df,
        "SCHWAB_API_PRICES_CSV": price_df,
        "SCHWAB_API_TRANSACTIONS_CSV": transactions_df,
        "SCHWAB_API_OPTION_CHAINS_CSV": option_chains_df,
        "SCHWAB_API_OPTION_RISK_CSV": option_risk_df,
        "SCHWAB_API_EVENTS_CSV": events_df,
        "SCHWAB_SOURCE_STATUS_CSV": source_status,
        "SCHWAB_SEC_FILINGS_CSV": sec_filings_df,
        "SCHWAB_MACRO_EVENTS_CSV": macro_events_df,
        "SCHWAB_CRYPTO_PRICES_CSV": crypto_prices_df,
        "SCHWAB_ANALYST_RATINGS_CSV": analyst_ratings_df,
        "SCHWAB_NEWS_HEADLINES_CSV": news_headlines_df,
    }
    legacy_tx = latest_by_name(processed.glob("schwab-transactions-normalized-*.csv"))
    legacy_summary = latest_by_name(processed.glob("schwab-symbol-summary-*.csv"))
    if legacy_tx:
        viewer_tables["SCHWAB_LEGACY_TX_CSV"] = pd.read_csv(legacy_tx)
    if legacy_summary:
        viewer_tables["SCHWAB_LEGACY_SUMMARY_CSV"] = pd.read_csv(legacy_summary)
    write_viewer_data(args.viewer_data, args.date, viewer_tables)

    print(f"accounts={len(accounts_df)}")
    print(f"positions={len(positions_df)}")
    print(f"symbols={len(symbols)}")
    print(f"quotes={len(quotes_df)}")
    print(f"price_rows={len(price_df)}")
    print(f"price_errors={len(price_errors_df)}")
    print(f"recent_transactions={len(transactions_df)}")
    print(f"events={len(events_df)} (dividends+earnings)")
    print(f"sec_filings={len(sec_filings_df)}")
    print(f"macro_events={len(macro_events_df)}")
    print(f"crypto_prices={len(crypto_prices_df)}")
    print(f"analyst_ratings={len(analyst_ratings_df)}")
    print(f"news_headlines={len(news_headlines_df)}")
    print(f"option_chains={len(option_chain_payloads)}")
    print(f"option_chain_rows={len(option_chains_df)}")
    print(f"option_risk_rows={len(option_risk_df)}")
    print(f"raw_sanitized={raw_path}")
    print(f"duckdb={db_path}")
    print(f"viewer_data={args.viewer_data}")


if __name__ == "__main__":
    main()
