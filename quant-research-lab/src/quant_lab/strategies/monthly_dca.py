from __future__ import annotations

from typing import Optional, Tuple

from backtesting import Strategy


class MonthlyDCAPrefundedStrategy(Strategy):
    contribution = 1000.0

    def init(self) -> None:
        self._last_month: Optional[Tuple[int, int]] = None

    def next(self) -> None:
        current_time = self.data.index[-1]
        current_month = (current_time.year, current_time.month)
        if current_month == self._last_month:
            return
        self._last_month = current_month

        price = float(self.data.Close[-1])
        quantity = int(float(self.contribution) // price)
        if quantity > 0:
            self.buy(size=quantity)
