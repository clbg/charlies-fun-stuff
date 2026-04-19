import unittest
from pathlib import Path

from backtesting import Backtest

from quant_lab.data.csv_loader import load_price_frame
from quant_lab.strategies.buy_and_hold import BuyAndHoldStrategy


class SmokeTest(unittest.TestCase):
    def test_buy_and_hold_smoke(self) -> None:
        root = Path(__file__).resolve().parent.parent
        frame = load_price_frame(str(root / "data/sample/amzn_monthly.csv"))
        backtest = Backtest(
            frame,
            BuyAndHoldStrategy,
            cash=10000,
            trade_on_close=True,
            finalize_trades=True,
        )
        stats = backtest.run()

        self.assertGreater(float(stats["Equity Final [$]"]), 10000.0)
        self.assertEqual(int(stats["# Trades"]), 1)


if __name__ == "__main__":
    unittest.main()
