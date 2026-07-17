#!/usr/bin/env python3
"""Read-only Schwab Trader API smoke test.

Requires a token created by `mise run auth`. Saves only sanitized response
samples for debugging.
"""

from __future__ import annotations

import argparse
import json
from datetime import date, datetime, timedelta
from pathlib import Path

import httpx
from schwab.auth import client_from_token_file
from schwab.client import Client

from .common import HISTORY_ROOT, cleanup_runtime_token, load_credentials, mask_tail, sanitize_api_payload, sync_token_to_dotenv, token_path


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--token-path", help="Override local token path.")
    parser.add_argument("--date", default=date.today().isoformat())
    parser.add_argument("--out-dir", default=str(HISTORY_ROOT / "processed"))
    parser.add_argument("--skip-price-history", action="store_true")
    return parser.parse_args()


def ok_json(response):
    if response.status_code != httpx.codes.OK:
        response.raise_for_status()
    return response.json()


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
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    try:
        account_numbers = ok_json(client.get_account_numbers())
        hashes = [row.get("hashValue") for row in account_numbers if row.get("hashValue")]
        print(f"accounts={len(hashes)}")
        print("account_hashes=" + ",".join(mask_tail(item) for item in hashes))

        accounts_payload = ok_json(client.get_accounts(fields=[Client.Account.Fields.POSITIONS]))
        position_count = 0
        for account in accounts_payload if isinstance(accounts_payload, list) else []:
            securities = account.get("securitiesAccount", {})
            position_count += len(securities.get("positions") or [])
        print(f"positions={position_count}")

        quotes_payload = ok_json(client.get_quotes(["SPY", "QQQ"]))
        print(f"quote_symbols={len(quotes_payload) if isinstance(quotes_payload, dict) else 0}")

        price_payload = {}
        if not args.skip_price_history:
            start = datetime.combine(date.today() - timedelta(days=14), datetime.min.time())
            end = datetime.combine(date.today(), datetime.min.time())
            price_payload = ok_json(client.get_price_history_every_day("AAPL", start_datetime=start, end_datetime=end))
            print(f"aapl_candles={len(price_payload.get('candles') or [])}")

        artifact = {
            "captured_at": datetime.now().isoformat(timespec="seconds"),
            "account_numbers": sanitize_api_payload(account_numbers),
            "accounts": sanitize_api_payload(accounts_payload),
            "quotes": sanitize_api_payload(quotes_payload),
            "aapl_price_history": sanitize_api_payload(price_payload),
        }
        artifact_path = out_dir / f"schwab-api-smoke-sanitized-{args.date}.json"
        artifact_path.write_text(json.dumps(artifact, indent=2, ensure_ascii=False), encoding="utf-8")
        print(f"artifact={artifact_path}")
    finally:
        if not args.token_path:
            sync_token_to_dotenv(path)
            cleanup_runtime_token(path)


if __name__ == "__main__":
    main()
