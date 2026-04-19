from __future__ import annotations

from typing import Iterable, Sequence

from quant_lab.backtest.models import Bar, Order, Portfolio


class Strategy:
    def __init__(self, **params) -> None:
        self.params = params

    def on_start(self, bars: Sequence[Bar], portfolio: Portfolio) -> None:
        return None

    def on_bar(self, bar: Bar, portfolio: Portfolio) -> Iterable[Order]:
        return []

    def on_finish(self, bars: Sequence[Bar], portfolio: Portfolio) -> None:
        return None
