from backtesting import Strategy


class BuyAndHoldStrategy(Strategy):
    def init(self) -> None:
        return None

    def next(self) -> None:
        if self.position:
            return
        price = float(self.data.Close[-1])
        quantity = int(self.equity // price)
        if quantity > 0:
            self.buy(size=quantity)
