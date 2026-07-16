#!/usr/bin/env python3
"""Create or refresh the local Schwab Trader API OAuth token.

This script only performs OAuth client creation. It does not place, cancel, or
modify orders.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from schwab.auth import client_from_login_flow, client_from_manual_flow, client_from_token_file

from .common import load_credentials, mask_tail, token_path


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--token-path", help="Override local token path. Defaults to $CODEX_HOME/secrets/schwab-trader-token.json.")
    parser.add_argument("--manual", action="store_true", help="Use copy/paste manual OAuth flow instead of local callback server.")
    parser.add_argument("--browser", help="Browser name passed to Python webbrowser, e.g. chrome.")
    parser.add_argument("--force-new-token", action="store_true", help="Delete existing token before starting OAuth.")
    parser.add_argument("--check-only", action="store_true", help="Only verify BWS/env secrets and token path; do not open OAuth.")
    parser.add_argument("--no-prompt", action="store_true", help="Start browser OAuth without waiting for an Enter key prompt.")
    return parser.parse_args()


def main():
    args = parse_args()
    creds = load_credentials()
    path = token_path(args.token_path)
    print(f"client_id={mask_tail(creds.client_id)}")
    print(f"callback_url={creds.callback_url}")
    print(f"token_path={path}")
    print(f"token_exists={path.exists()}")

    if args.check_only:
        return

    if args.force_new_token and path.exists():
        path.unlink()
        print("old_token_removed=true")

    if path.exists():
        client = client_from_token_file(
            str(path),
            api_key=creds.client_id,
            app_secret=creds.client_secret,
            enforce_enums=False,
        )
    elif args.manual:
        client = client_from_manual_flow(
            api_key=creds.client_id,
            app_secret=creds.client_secret,
            callback_url=creds.callback_url,
            token_path=str(path),
            enforce_enums=False,
        )
    else:
        client = client_from_login_flow(
            api_key=creds.client_id,
            app_secret=creds.client_secret,
            callback_url=creds.callback_url,
            token_path=str(path),
            enforce_enums=False,
            callback_timeout=600,
            interactive=not args.no_prompt,
            requested_browser=args.browser,
        )

    print(f"token_created_or_loaded={Path(path).exists()}")
    try:
        print(f"token_age_seconds={int(client.token_age())}")
    except Exception:
        print("token_age_seconds=unknown")


if __name__ == "__main__":
    main()
