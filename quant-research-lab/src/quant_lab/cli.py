from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any, Dict

from backtesting import Backtest

from quant_lab.data.csv_loader import load_price_frame
from quant_lab.strategies import STRATEGIES


def main() -> None:
    parser = argparse.ArgumentParser(prog="quant-lab")
    subparsers = parser.add_subparsers(dest="command", required=True)

    run_parser = subparsers.add_parser("run", help="Run an experiment config.")
    run_parser.add_argument("config", help="Path to experiment JSON config.")

    list_parser = subparsers.add_parser("list-strategies", help="List available strategies.")

    args = parser.parse_args()
    if args.command == "run":
        run_experiment(args.config)
    elif args.command == "list-strategies":
        for name in sorted(STRATEGIES):
            print(name)


def run_experiment(config_path: str) -> None:
    config = _load_config(config_path)
    config_file = Path(config_path).resolve()
    data_path = (config_file.parent / config["data_path"]).resolve()
    if not data_path.exists():
        data_path = Path(config["data_path"]).expanduser().resolve()

    frame = load_price_frame(str(data_path))
    strategy_cfg = config["strategy"]
    strategy_cls = STRATEGIES[strategy_cfg["name"]]

    initial_cash = float(config["initial_cash"])
    bt = Backtest(
        frame,
        strategy_cls,
        cash=initial_cash,
        commission=float(config.get("commission", 0.0)),
        exclusive_orders=bool(config.get("exclusive_orders", True)),
        trade_on_close=bool(config.get("trade_on_close", True)),
        finalize_trades=bool(config.get("finalize_trades", True)),
    )
    stats = bt.run(**strategy_cfg.get("params", {}))

    print(f"Experiment: {config.get('name', config_file.stem)}")
    print(f"Data:       {config['data_path']}")
    print(f"Strategy:   {strategy_cfg['name']}")
    print(f"Bars:       {len(frame)}")
    print("")
    rows = [
        ("final_equity", float(stats["Equity Final [$]"])),
        ("total_return", float(stats["Return [%]"]) / 100.0),
        ("buy_hold_return", float(stats["Buy & Hold Return [%]"]) / 100.0),
        ("cagr", float(stats.get("CAGR [%]", 0.0)) / 100.0),
        ("max_drawdown", float(stats["Max. Drawdown [%]"]) / 100.0),
        ("annualized_vol", float(stats.get("Volatility (Ann.) [%]", 0.0)) / 100.0),
        ("trade_count", int(stats["# Trades"])),
    ]
    for key, value in rows:
        if key in {"total_return", "buy_hold_return", "cagr", "max_drawdown", "annualized_vol"}:
            print(f"{key:16} {value:>10.2%}")
        elif key == "trade_count":
            print(f"{key:16} {value:>10}")
        else:
            print(f"{key:16} {value:>10.2f}")


def _load_config(path: str) -> Dict[str, Any]:
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


if __name__ == "__main__":
    main()
