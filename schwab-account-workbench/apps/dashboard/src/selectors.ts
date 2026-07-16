import type { LegacyTx, PortfolioData, Position, Quote } from "./types.ts";
import { positionDayPnl, quoteMap } from "./metrics.ts";

export function accountValue(data: PortfolioData): number {
  return (
    data.accounts[0]?.liquidation_value_num ??
    data.positions.reduce((s, r) => s + (r.market_value_num ?? 0), 0)
  );
}

export function longPositions(data: PortfolioData): Position[] {
  return data.positions.filter((r) => r.asset_type !== "OPTION");
}

export function quoteFor(data: PortfolioData, symbol: string): Quote | undefined {
  return data.quotes.find((q) => q.symbol === symbol || q.symbol === symbol?.trim());
}

export interface Grouped {
  symbol: string;
  rows: Position[];
  marketValue: number;
  dayPnL: number;
  openPnL: number;
  quantity: number;
}

export function groupPositions(data: PortfolioData, symbol: string, qmap: Map<string, Quote>): Grouped {
  const rows = data.positions.filter((r) => (r.underlying || r.symbol) === symbol);
  return {
    symbol,
    rows,
    marketValue: rows.reduce((s, r) => s + (r.market_value_num ?? 0), 0),
    dayPnL: rows.reduce((s, r) => s + positionDayPnl(r, qmap), 0),
    openPnL: rows.reduce((s, r) => s + (r.long_open_profit_loss_num ?? 0), 0),
    quantity: rows.reduce((s, r) => s + (r.net_quantity_num ?? 0), 0),
  };
}

export function legacyRowsFor(data: PortfolioData, symbol: string): LegacyTx[] {
  return data.legacyTransactions.filter((r) => r.underlying === symbol || r.symbol === symbol);
}

export function currentSymbols(data: PortfolioData): string[] {
  return [...new Set(data.positions.map((r) => r.underlying || r.symbol).filter(Boolean))];
}

export function allSymbols(data: PortfolioData): string[] {
  return [
    ...new Set([
      ...currentSymbols(data),
      ...data.legacyTransactions.map((r) => r.underlying).filter(Boolean),
    ]),
  ];
}

const TECH = ["AMZN", "GOOG", "GOOGL", "AAPL", "NVDA", "META", "QCOM", "INTC", "MU"];

export function categoryFor(row: Position): string {
  const symbol = row.underlying || row.symbol;
  if (row.asset_type === "OPTION") return "Options";
  if (["BOXX", "SGOV"].includes(symbol)) return "Cash-like";
  if (TECH.includes(symbol)) return "US tech";
  if (["T", "MCD", "GLW"].includes(symbol)) return "US consumer/telco";
  if (["TSLA", "SE"].includes(symbol)) return "Growth/speculative";
  if (["QQQ", "SPY", "USMV", "GPIQ"].includes(symbol)) return "Broad market ETF";
  if (["PSI", "SOXX", "SMH"].includes(symbol)) return "Semiconductor ETF";
  if (["IBIT", "BTCO"].includes(symbol)) return "Bitcoin ETF";
  if (["BAR"].includes(symbol)) return "Gold";
  if (["CPER", "COPX", "DBO", "BDRY"].includes(symbol)) return "Commodities";
  if (["INDA"].includes(symbol)) return "International";
  if (row.asset_type === "COLLECTIVE_INVESTMENT" || row.asset_type === "ETF") return "Other ETF";
  return row.asset_type === "EQUITY" ? "Other equity" : "Other";
}

export { quoteMap };
