# Quant Research Lab

Minimal research platform for quickly testing trading ideas without mixing code into the vault.

## What It Includes

- `backtesting.py` as the backtest engine
- CSV market data loader that converts simple `date,close` data into OHLCV
- Two sample strategies:
  - `buy_and_hold`
  - `monthly_dca_prefunded`
- JSON experiment configs

## Quick Start

Create a local environment and install dependencies:

```bash
cd /Users/pengcheng/projects/charlies-fun-stuff/quant-research-lab
mise install
mise run install
```

Run the sample experiments:

```bash
cd /Users/pengcheng/projects/charlies-fun-stuff/quant-research-lab
mise run run-buy-and-hold
mise run run-dca
mise run list-strategies
```

## Project Layout

```text
quant-research-lab/
  data/sample/              Sample CSV data
  experiments/              JSON experiment configs
  src/quant_lab/
    data/                   CSV loading
    strategies/             Strategy implementations
    cli.py                  CLI entry point
  tests/                    Lightweight verification tests
```

## CSV Format

The loader expects at least:

```text
date,close
2023-01-03,85.82
2023-02-01,102.18
```

- `date` must be ISO format `YYYY-MM-DD`
- `close` is promoted to `Open` / `High` / `Low` / `Close`
- `Volume` is set to `0` when missing

## Adding a New Strategy

1. Add a class in `src/quant_lab/strategies/`
2. Inherit from `backtesting.Strategy`
3. Implement `init()` and/or `next()`
3. Register it in `src/quant_lab/strategies/__init__.py`
4. Point an experiment config to it

## Current Scope

This scaffold is intentionally small:

- long-only cash equities
- daily or coarser bar data
- no fees, slippage, or dividends yet
- no options handling yet

That is enough to validate ideas, compare rules, and evolve the platform. The next logical step is a covered call teaching layer on top of historical AMZN data.
