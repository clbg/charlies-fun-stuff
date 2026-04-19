from __future__ import annotations

import math
from statistics import pstdev
from typing import Dict, Iterable, List

from quant_lab.backtest.engine import BacktestResult


def summarize(result: BacktestResult, initial_cash: float) -> Dict[str, float]:
    equity = [point.equity for point in result.equity_curve]
    if not equity:
        return {}

    capital_base = result.contributed_capital if result.contributed_capital > 0 else initial_cash
    capital_base = capital_base if capital_base > 0 else 1.0

    total_return = equity[-1] / capital_base - 1.0
    days = max((result.equity_curve[-1].date - result.equity_curve[0].date).days, 1)
    cagr = (equity[-1] / capital_base) ** (365.0 / days) - 1.0

    running_peak = equity[0]
    max_drawdown = 0.0
    returns: List[float] = []
    for previous, current in zip(equity, equity[1:]):
        running_peak = max(running_peak, current)
        drawdown = current / running_peak - 1.0
        max_drawdown = min(max_drawdown, drawdown)
        returns.append(current / previous - 1.0)

    periods_per_year = _estimate_periods_per_year(result)
    annualized_vol = pstdev(returns) * math.sqrt(periods_per_year) if len(returns) > 1 else 0.0

    return {
        "contributed_capital": capital_base,
        "final_equity": equity[-1],
        "total_return": total_return,
        "cagr": cagr,
        "max_drawdown": max_drawdown,
        "annualized_vol": annualized_vol,
        "trade_count": float(len(result.trades)),
    }


def _estimate_periods_per_year(result: BacktestResult) -> float:
    if len(result.equity_curve) < 2:
        return 12.0
    gaps = [
        (current.date - previous.date).days
        for previous, current in zip(result.equity_curve, result.equity_curve[1:])
        if (current.date - previous.date).days > 0
    ]
    if not gaps:
        return 12.0
    median_gap = sorted(gaps)[len(gaps) // 2]
    return max(1.0, 365.0 / median_gap)
