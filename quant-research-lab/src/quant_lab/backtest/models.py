from __future__ import annotations

from dataclasses import dataclass
from datetime import date
from typing import Optional


@dataclass
class Bar:
    date: date
    close: float


@dataclass
class Portfolio:
    cash: float
    shares: int = 0

    def equity(self, price: float) -> float:
        return self.cash + self.shares * price


@dataclass
class Order:
    quantity: int
    note: str = ""


@dataclass
class Trade:
    date: date
    quantity: int
    price: float
    cash_after: float
    shares_after: int
    note: str = ""


@dataclass
class EquityPoint:
    date: date
    close: float
    cash: float
    shares: int
    equity: float
    trade_note: Optional[str] = None
