from quant_lab.strategies.buy_and_hold import BuyAndHoldStrategy
from quant_lab.strategies.monthly_dca import MonthlyDCAPrefundedStrategy

STRATEGIES = {
    "buy_and_hold": BuyAndHoldStrategy,
    "monthly_dca_prefunded": MonthlyDCAPrefundedStrategy,
}

__all__ = ["STRATEGIES", "BuyAndHoldStrategy", "MonthlyDCAPrefundedStrategy"]
