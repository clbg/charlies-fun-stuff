// Pure, unit-testable portfolio metrics. Every one of the bugs found in the
// original single-file viewer lives here as a tested function instead of being
// inlined into render code.

import type { LegacyTx, Position, PriceRow, Quote } from "./types.ts";
import { num } from "./format.ts";

/**
 * Day P&L for a position, corrected for Schwab's occasionally-corrupt
 * `currentDayProfitLoss`. For non-option positions with a live quote,
 * `net_quantity × quote.net_change` is the definitional day P&L from the same
 * API and is trustworthy. BOXX once reported $5,873 on a day the quote moved
 * only $0.02 (a nonsensical ~34% daily move); the true value was ~$2.96.
 */
export function positionDayPnl(
  position: Position,
  quoteBySymbol: Map<string, Quote>,
): number {
  if (position.asset_type !== "OPTION") {
    const quote = quoteBySymbol.get(position.underlying || position.symbol);
    const netChange = quote?.net_change_num ?? null;
    const netQty = position.net_quantity_num;
    if (netChange != null && netQty != null) return netQty * netChange;
  }
  return position.current_day_profit_loss_num ?? 0;
}

export function quoteMap(quotes: Quote[]): Map<string, Quote> {
  return new Map(quotes.map((q) => [q.symbol, q]));
}

export function accountDayPnl(
  positions: Position[],
  quoteBySymbol: Map<string, Quote>,
): number {
  return positions.reduce((sum, p) => sum + positionDayPnl(p, quoteBySymbol), 0);
}

/**
 * Signed net contracts for an option leg. A short call/put is negative
 * exposure; the old `short_qty || long_qty` treated shorts as positive and
 * inverted delta dollars.
 */
export function netContracts(longQty: number, shortQty: number): number {
  return longQty - shortQty;
}

export function deltaDollars(
  delta: number | null,
  longQty: number,
  shortQty: number,
  underlyingPrice: number,
): number {
  return (delta ?? 0) * netContracts(longQty, shortQty) * 100 * underlyingPrice;
}

export type OptionStatus = "TRADE" | "EXPIRED" | "ASSIGNED";

export function optionEventStatus(action: string): OptionStatus {
  const text = (action || "").toLowerCase();
  if (text.includes("expired")) return "EXPIRED";
  if (text.includes("assigned")) return "ASSIGNED";
  return "TRADE";
}

function isOption(row: LegacyTx): boolean {
  return row.instrument_type === "option" || row.asset_type === "OPTION";
}

/** Most recent close on or before `date` (weekend/holiday fallback). */
export function underlyingCloseOn(
  sortedPrices: PriceRow[],
  date: string,
): number | null {
  if (!date) return null;
  let close: number | null = null;
  for (const row of sortedPrices) {
    if (row.close_num == null || !row.date) continue;
    if (row.date <= date) close = row.close_num;
    else break;
  }
  return close;
}

export interface OptionEventPoint {
  date: string;
  close: number;
  status: OptionStatus;
  contract: string;
  expiration: string;
  premium: number | null;
  side: string;
  action: string;
}

/**
 * Project option executions onto the UNDERLYING's daily close instead of the
 * option premium ($1–2), because premium and share price are different
 * quantities and must not share the price axis.
 */
export function projectOptionEvents(
  symbol: string,
  rows: LegacyTx[],
  sortedPrices: PriceRow[],
): OptionEventPoint[] {
  return rows
    .filter((r) => r.trade_date && isOption(r))
    .map((r): OptionEventPoint | null => {
      const close = underlyingCloseOn(sortedPrices, r.trade_date);
      if (close == null) return null;
      const optType = String(r.option_type || r.put_call || "").slice(0, 1);
      return {
        date: r.trade_date,
        close,
        status: optionEventStatus(r.action),
        contract: `${r.underlying || symbol} ${r.option_strike ?? ""}${optType}`.trim(),
        expiration: r.option_expiration || "",
        premium: r.price_num,
        side: r.side,
        action: r.action || "",
      };
    })
    .filter((p): p is OptionEventPoint => p !== null);
}

export interface StockExecution {
  date: string;
  price: number;
  side: string;
}

export function stockExecutions(rows: LegacyTx[]): StockExecution[] {
  return rows
    .filter((r) => r.trade_date && !isOption(r) && r.price_num != null)
    .map((r) => ({ date: r.trade_date, price: r.price_num as number, side: r.side }));
}

export interface CashPoint {
  date: string;
  flow: number;
  cumulative: number;
  action: string;
  symbol: string;
  side: string;
}

/** Running cumulative net cash (in/out), NOT a profit curve. */
export function cumulativeCash(rows: LegacyTx[]): CashPoint[] {
  let cumulative = 0;
  return rows
    .slice()
    .sort(
      (a, b) =>
        (a.trade_date || "").localeCompare(b.trade_date || "") ||
        (num(a.source_row) ?? 0) - (num(b.source_row) ?? 0),
    )
    .map((r) => {
      cumulative += r.cash_flow_num ?? 0;
      return {
        date: r.trade_date,
        flow: r.cash_flow_num ?? 0,
        cumulative,
        action: r.action || "",
        symbol: r.symbol || r.underlying || "",
        side: r.side,
      };
    });
}

export function sortPricesFor(symbol: string, prices: PriceRow[]): PriceRow[] {
  return prices
    .filter((r) => r.symbol === symbol)
    .sort((a, b) => (a.date || "").localeCompare(b.date || ""));
}
