import { describe, it, expect } from "vitest";
import {
  positionDayPnl,
  quoteMap,
  netContracts,
  deltaDollars,
  optionEventStatus,
  underlyingCloseOn,
  projectOptionEvents,
  cumulativeCash,
} from "./metrics.ts";
import type { Position, Quote, LegacyTx, PriceRow } from "./types.ts";

function pos(p: Partial<Position>): Position {
  return {
    symbol: "X", underlying: "X", description: "", asset_type: "EQUITY",
    net_quantity_num: null, market_value_num: null,
    current_day_profit_loss_num: null, long_open_profit_loss_num: null,
    average_price_num: null, ...p,
  };
}

describe("positionDayPnl — BOXX reconciliation", () => {
  it("recomputes day P&L from net_qty × quote net_change, not the corrupt API field", () => {
    const boxx = pos({
      symbol: "BOXX", underlying: "BOXX", asset_type: "COLLECTIVE_INVESTMENT",
      net_quantity_num: 147.7515,
      current_day_profit_loss_num: 5873.455, // corrupt Schwab value
    });
    const quotes = quoteMap([
      { symbol: "BOXX", last_price_num: 117.42, mark_num: null, net_change_num: 0.02 } as Quote,
    ]);
    expect(positionDayPnl(boxx, quotes)).toBeCloseTo(2.955, 2);
  });

  it("falls back to the API field when no quote net_change exists", () => {
    const p = pos({ symbol: "ZZZ", underlying: "ZZZ", net_quantity_num: 10, current_day_profit_loss_num: 42 });
    expect(positionDayPnl(p, quoteMap([]))).toBe(42);
  });

  it("never quote-reconciles option legs (premium != share move)", () => {
    const opt = pos({ symbol: "O", underlying: "AMZN", asset_type: "OPTION", net_quantity_num: -1, current_day_profit_loss_num: 12.5 });
    const quotes = quoteMap([{ symbol: "AMZN", last_price_num: 250, mark_num: null, net_change_num: 3 } as Quote]);
    expect(positionDayPnl(opt, quotes)).toBe(12.5);
  });
});

describe("option delta direction", () => {
  it("short 1 put => net -1 contract", () => {
    expect(netContracts(0, 1)).toBe(-1);
  });

  it("short put delta dollars is positive (bullish), fixing the inverted sign", () => {
    // GOOGL 352.5P short 1, delta -0.381, underlying ~356 => old code gave -13571.
    const dd = deltaDollars(-0.381, 0, 1, 356.13);
    expect(dd).toBeGreaterThan(0);
    expect(dd).toBeCloseTo(13568.6, 0);
  });
});

describe("optionEventStatus", () => {
  it("classifies expired / assigned / trade", () => {
    expect(optionEventStatus("Expired")).toBe("EXPIRED");
    expect(optionEventStatus("Assigned")).toBe("ASSIGNED");
    expect(optionEventStatus("Sell to Open")).toBe("TRADE");
    expect(optionEventStatus("Buy to Close")).toBe("TRADE");
  });
});

const prices: PriceRow[] = [
  { symbol: "GOOGL", date: "2026-07-10", close_num: 350 },
  { symbol: "GOOGL", date: "2026-07-13", close_num: 352.51 },
];

describe("underlyingCloseOn", () => {
  it("returns exact-day close", () => {
    expect(underlyingCloseOn(prices, "2026-07-13")).toBe(352.51);
  });
  it("falls back to most recent prior close on a gap day", () => {
    expect(underlyingCloseOn(prices, "2026-07-12")).toBe(350);
  });
  it("returns null before any price history", () => {
    expect(underlyingCloseOn(prices, "2026-07-01")).toBeNull();
  });
});

describe("projectOptionEvents", () => {
  it("projects option premium onto underlying close, not premium level", () => {
    const rows: LegacyTx[] = [
      {
        trade_date: "2026-07-13", action: "Sell to Open", symbol: "GOOGL 07/20/2026 352.50 P",
        underlying: "GOOGL", instrument_type: "option", option_type: "PUT",
        option_strike: "352.5", side: "sell", price_num: 4.17, cash_flow_num: 416.33,
      } as LegacyTx,
    ];
    const [ev] = projectOptionEvents("GOOGL", rows, prices);
    expect(ev.close).toBe(352.51); // on the price line
    expect(ev.premium).toBe(4.17); // premium retained for tooltip only
    expect(ev.status).toBe("TRADE");
  });
});

describe("cumulativeCash", () => {
  it("accumulates net cash and preserves per-row flow", () => {
    const rows: LegacyTx[] = [
      { trade_date: "2026-01-01", action: "Buy", symbol: "A", underlying: "A", instrument_type: "equity_or_etf", side: "buy", price_num: 1, cash_flow_num: -100 } as LegacyTx,
      { trade_date: "2026-01-02", action: "Sell", symbol: "A", underlying: "A", instrument_type: "equity_or_etf", side: "sell", price_num: 1, cash_flow_num: 30 } as LegacyTx,
    ];
    const pts = cumulativeCash(rows);
    expect(pts.map((p) => p.cumulative)).toEqual([-100, -70]);
  });
});
