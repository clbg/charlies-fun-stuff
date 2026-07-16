"""Publish the built dashboard artifact to the vault."""

from __future__ import annotations

import shutil
from pathlib import Path

from .common import HISTORY_ROOT, PROJECT_ROOT


def main() -> None:
    source = PROJECT_ROOT / "apps/dashboard/dist/index.html"
    if not source.exists():
        raise SystemExit(f"Dashboard build not found: {source}. Run `mise run build` first.")

    target = HISTORY_ROOT / "viewer-react/dist/index.html"
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)
    print(f"published={target}")


if __name__ == "__main__":
    main()
