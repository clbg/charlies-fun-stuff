#!/usr/bin/env python3
"""Shared helpers for read-only Schwab Trader API scripts.

Secrets are loaded from Bitwarden Secrets Manager or environment variables.
Never print the returned credential values.
"""

from __future__ import annotations

import json
import os
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[2]
CODE_ROOT = PROJECT_ROOT


def _default_vault_root() -> Path:
    env_root = os.environ.get("CHARLIE_VAULT_ROOT")
    if env_root:
        return Path(env_root).expanduser()
    drive_root = os.environ.get("G_DRIVE_AUTO_SYNC_PATH")
    if drive_root:
        return Path(drive_root).expanduser() / "CharlieObsidianVault"
    return Path.home() / "Library/CloudStorage/GoogleDrive-charlie.pengcheng@gmail.com/My Drive/Autosync/CharlieObsidianVault"


VAULT_ROOT = _default_vault_root()
HISTORY_ROOT = Path(os.environ.get("SCHWAB_HISTORY_ROOT", VAULT_ROOT / "Investment/Portfolio/SchwabHistory")).expanduser()
ENV_TOKEN_KEY = "SCHWAB_TRADER_TOKEN_JSON"
DEFAULT_TOKEN_PATH = Path(
    os.environ.get(
        "SCHWAB_TRADER_TOKEN_FILE",
        Path(tempfile.gettempdir()) / "schwab-workbench" / "schwab-trader-token.json",
    )
)


@dataclass(frozen=True)
class SchwabApiCredentials:
    client_id: str
    client_secret: str
    callback_url: str


def load_dotenv(path: Path | None = None) -> None:
    env_path = path or VAULT_ROOT / ".env"
    if not env_path.exists():
        return
    for line in env_path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        os.environ.setdefault(key, value)


def _dotenv_path() -> Path:
    return VAULT_ROOT / ".env"


def _format_env_value(value: str) -> str:
    return "'" + value.replace("'", "'\"'\"'") + "'"


def set_dotenv_secret(key: str, value: str, path: Path | None = None) -> None:
    env_path = path or _dotenv_path()
    env_path.parent.mkdir(parents=True, exist_ok=True)
    lines = env_path.read_text(encoding="utf-8").splitlines() if env_path.exists() else []
    replacement = f"{key}={_format_env_value(value)}"
    for idx, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith(f"{key}="):
            lines[idx] = replacement
            break
    else:
        if lines and lines[-1].strip():
            lines.append("")
        lines.append("# Schwab Trader API OAuth token JSON")
        lines.append(replacement)
    env_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    os.environ[key] = value


def _env_token_json() -> str | None:
    load_dotenv()
    token_json = os.environ.get(ENV_TOKEN_KEY)
    if not token_json:
        return None
    try:
        json.loads(token_json)
    except json.JSONDecodeError as exc:
        raise SystemExit(f"{ENV_TOKEN_KEY} in vault .env is not valid JSON: {exc}") from exc
    return token_json


def materialize_env_token(path: Path) -> None:
    token_json = _env_token_json()
    if not token_json:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(json.loads(token_json), separators=(",", ":")), encoding="utf-8")
    path.chmod(0o600)


def sync_token_to_dotenv(path: Path) -> None:
    if not path.exists():
        return
    token_json = path.read_text(encoding="utf-8")
    try:
        compact = json.dumps(json.loads(token_json), separators=(",", ":"))
    except json.JSONDecodeError as exc:
        raise SystemExit(f"Token file is not valid JSON: {path}") from exc
    set_dotenv_secret(ENV_TOKEN_KEY, compact)


def cleanup_runtime_token(path: Path) -> None:
    if path.resolve() != DEFAULT_TOKEN_PATH.expanduser().resolve():
        return
    try:
        path.unlink()
    except FileNotFoundError:
        pass


def _bws_secret_list() -> list[dict]:
    load_dotenv()
    result = subprocess.run(
        ["bws", "secret", "list", "--output", "json"],
        check=True,
        capture_output=True,
        text=True,
        env=os.environ.copy(),
    )
    return json.loads(result.stdout)


def bws_secret_value(key: str) -> str | None:
    try:
        secrets = _bws_secret_list()
    except (subprocess.CalledProcessError, FileNotFoundError, json.JSONDecodeError):
        return None
    secret_id = next((item.get("id") for item in secrets if item.get("key") == key), None)
    if not secret_id:
        return None
    try:
        result = subprocess.run(
            ["bws", "secret", "get", secret_id, "--output", "json"],
            check=True,
            capture_output=True,
            text=True,
            env=os.environ.copy(),
        )
        payload = json.loads(result.stdout)
    except (subprocess.CalledProcessError, FileNotFoundError, json.JSONDecodeError):
        return None
    value = payload.get("value")
    return str(value) if value else None


def secret_value(key: str) -> str | None:
    load_dotenv()
    return os.environ.get(key) or bws_secret_value(key)


def load_credentials() -> SchwabApiCredentials:
    missing = []
    client_id = secret_value("SCHWAB_TRADER_CLIENT_ID")
    if not client_id:
        missing.append("SCHWAB_TRADER_CLIENT_ID")
    client_secret = secret_value("SCHWAB_TRADER_CLIENT_SECRET")
    if not client_secret:
        missing.append("SCHWAB_TRADER_CLIENT_SECRET")
    callback_url = secret_value("SCHWAB_TRADER_CALLBACK_URL")
    if not callback_url:
        missing.append("SCHWAB_TRADER_CALLBACK_URL")
    if missing:
        raise SystemExit(f"Missing Schwab Trader API secrets: {', '.join(missing)}")
    return SchwabApiCredentials(client_id=client_id, client_secret=client_secret, callback_url=callback_url)


def token_path(path: str | None = None) -> Path:
    resolved = Path(path).expanduser() if path else DEFAULT_TOKEN_PATH
    resolved.parent.mkdir(parents=True, exist_ok=True)
    if not path:
        materialize_env_token(resolved)
    return resolved


def mask_tail(value: str | None, visible: int = 4) -> str:
    if not value:
        return ""
    text = str(value)
    if len(text) <= visible:
        return "*" * len(text)
    return f"...{text[-visible:]}"


def sanitize_api_payload(value):
    """Remove fields that should never be persisted in local artifacts."""
    blocked = {
        "accountNumber": "acct_tail",
        "accountId": "acct_id_tail",
        "accountHash": "acct_hash_tail",
        "hashValue": "acct_hash_tail",
        "authorization": "auth_tail",
        "Authorization": "auth_tail",
        "access_token": "access_tail",
        "refresh_token": "refresh_tail",
        "token": "token_tail",
    }
    if isinstance(value, dict):
        cleaned = {}
        for key, item in value.items():
            if key in blocked:
                cleaned[blocked[key]] = mask_tail(str(item)) if item else item
            else:
                cleaned[key] = sanitize_api_payload(item)
        return cleaned
    if isinstance(value, list):
        return [sanitize_api_payload(item) for item in value]
    return value
