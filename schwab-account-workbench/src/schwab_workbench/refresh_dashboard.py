#!/usr/bin/env python3
"""Refresh the Schwab dashboard data.

The dashboard reads the ``SCHWAB_API_*`` variables produced by
``schwab_workbench.api_refresh``. That is the primary, supported data path, so
"refresh the dashboard" delegates to it.

Historically this script called ``build_history_db.py``, the legacy
CSV-only builder. That builder writes ``viewer/data.js`` in the old
``SCHWAB_TX_CSV`` shape, which the current viewer cannot read — running it would
leave the dashboard showing "Load failed". The legacy builder is still available
for archival DuckDB rebuilds, but it no longer runs from here and no longer
overwrites the live viewer unless you explicitly pass ``--write-viewer`` to it.
"""

import subprocess
import sys
from datetime import date

def main():
    # Delegate to the primary Schwab Trader API refresh. Forward any extra args
    # (e.g. --date, --skip-option-chains) straight through.
    cmd = [sys.executable, "-m", "schwab_workbench.api_refresh"]
    if not any(arg == "--date" or arg.startswith("--date=") for arg in sys.argv[1:]):
        cmd += ["--date", date.today().isoformat()]
    cmd += sys.argv[1:]

    print(f"delegating to: {' '.join(cmd)}", flush=True)
    print(
        "note: legacy CSV builder (schwab_workbench.build_history_db) is no longer run here; "
        "it would overwrite viewer/data.js with an incompatible schema.",
        flush=True,
    )
    raise SystemExit(subprocess.run(cmd, check=False).returncode)


if __name__ == "__main__":
    main()
