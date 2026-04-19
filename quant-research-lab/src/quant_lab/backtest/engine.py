from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable, List, Sequence

from quant_lab.backtest.models import Bar, EquityPoint, Order, Portfolio, Trade


@dataclass
class BacktestResult:
    portfolio: Portfolio
    trades: List[Trade]
    equity_curve: List[EquityPoint]
    contributed_capital: float


class BacktestEngine:
    def __init__(self, bars: Sequence[Bar], initial_cash: float) -> None:
        self.bars = list(bars)
        self.initial_cash = initial_cash

    def run(self, strategy) -> BacktestResult:
        portfolio = Portfolio(cash=self.initial_cash, shares=0)
        trades: List[Trade] = []
        equity_curve: List[EquityPoint] = []
        contributed_capital = self.initial_cash

        strategy.on_start(self.bars, portfolio)

        for bar in self.bars:
            cash_before_strategy = portfolio.cash
            orders = list(strategy.on_bar(bar, portfolio))
            if portfolio.cash > cash_before_strategy:
                contributed_capital += portfolio.cash - cash_before_strategy
            trade_note = None
            for order in orders:
                if order.quantity == 0:
                    continue
                cost = order.quantity * bar.close
                if order.quantity > 0 and cost > portfolio.cash:
                    affordable = int(portfolio.cash // bar.close)
                    if affordable <= 0:
                        continue
                    order = Order(quantity=affordable, note=order.note)
                    cost = order.quantity * bar.close
                portfolio.cash -= cost
                portfolio.shares += order.quantity
                trades.append(
                    Trade(
                        date=bar.date,
                        quantity=order.quantity,
                        price=bar.close,
                        cash_after=portfolio.cash,
                        shares_after=portfolio.shares,
                        note=order.note,
                    )
                )
                trade_note = order.note or None

            equity_curve.append(
                EquityPoint(
                    date=bar.date,
                    close=bar.close,
                    cash=portfolio.cash,
                    shares=portfolio.shares,
                    equity=portfolio.equity(bar.close),
                    trade_note=trade_note,
                )
            )

        strategy.on_finish(self.bars, portfolio)
        return BacktestResult(
            portfolio=portfolio,
            trades=trades,
            equity_curve=equity_curve,
            contributed_capital=contributed_capital,
        )
