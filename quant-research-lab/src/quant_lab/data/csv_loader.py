from __future__ import annotations

from pathlib import Path

import pandas as pd


def load_price_frame(path: str) -> pd.DataFrame:
    csv_path = Path(path)
    frame = pd.read_csv(csv_path)
    frame["date"] = pd.to_datetime(frame["date"])
    frame = frame.sort_values("date").set_index("date")

    if "close" not in frame.columns:
        raise ValueError("CSV must contain a 'close' column.")

    close = frame["close"].astype(float)
    result = pd.DataFrame(
        {
            "Open": close,
            "High": close,
            "Low": close,
            "Close": close,
            "Volume": frame["volume"].fillna(0).astype(float) if "volume" in frame.columns else 0.0,
        },
        index=frame.index,
    )
    return result
