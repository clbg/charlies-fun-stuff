import { describe, it, expect } from "vitest";
import { buildMonthGrids, parseISODate, daysBetween, urgencyOf } from "./calendar.ts";
import type { OptionRisk, PortfolioEvent } from "./types.ts";

function risk(p: Partial<OptionRisk>): OptionRisk {
  return {
    symbol: "X", underlying: "X", put_call: "PUT", expiration: "",
    strike_num: 100, short_quantity_num: 1, long_quantity_num: 0,
    net_contracts_num: -1, days_to_expiration_num: null, delta_num: null,
    theta_num: null, iv_num: null, assignment_notional_num: 10000,
    delta_dollars_num: null, ...p,
  };
}

describe("date helpers", () => {
  it("parses valid ISO dates in UTC", () => {
    expect(parseISODate("2026-07-20")?.day).toBe(20);
    expect(parseISODate("not-a-date")).toBeNull();
    expect(parseISODate("2026-02-30")).toBeNull(); // invalid calendar day
  });
  it("computes calendar days between dates", () => {
    expect(daysBetween("2026-07-15", "2026-07-22")).toBe(7);
  });
  it("classifies urgency", () => {
    expect(urgencyOf(3)).toBe("urgent");
    expect(urgencyOf(14)).toBe("soon");
    expect(urgencyOf(60)).toBe("later");
    expect(urgencyOf(null)).toBe("unknown");
  });
});

describe("buildMonthGrids", () => {
  const options: OptionRisk[] = [
    risk({ underlying: "GOOGL", expiration: "2026-07-20", strike_num: 352.5 }),
    risk({ underlying: "AMZN", expiration: "2026-08-15", strike_num: 255 }),
  ];
  const events: PortfolioEvent[] = [
    { symbol: "AAPL", event_type: "dividend_ex", event_date: "2026-08-11", detail: "Ex-dividend · $1.08/sh" },
    { symbol: "GOOGL", event_type: "earnings", event_date: "2026-07-22", detail: "Earnings (est.)" },
  ];

  it("creates one grid per month spanning options + events", () => {
    const { grids } = buildMonthGrids(options, events, "2026-07-15");
    expect(grids.map((g) => g.label)).toEqual(["July 2026", "August 2026"]);
  });

  it("places an option on its expiration day cell", () => {
    const { grids } = buildMonthGrids(options, [], "2026-07-15");
    const july = grids[0];
    const cell = july.weeks.flat().find((c) => c.date === "2026-07-20");
    expect(cell?.entries[0]?.risk.underlying).toBe("GOOGL");
    expect(cell?.dte).toBe(5);
    expect(cell?.urgency).toBe("urgent");
  });

  it("places dividend + earnings events on their day cells", () => {
    const { grids } = buildMonthGrids([], events, "2026-07-15");
    const jul = grids.find((g) => g.label === "July 2026")!;
    const earnCell = jul.weeks.flat().find((c) => c.date === "2026-07-22");
    expect(earnCell?.events[0]?.event_type).toBe("earnings");
    const aug = grids.find((g) => g.label === "August 2026")!;
    const divCell = aug.weeks.flat().find((c) => c.date === "2026-08-11");
    expect(divCell?.events[0]?.symbol).toBe("AAPL");
  });

  it("weeks are always 7 cells wide", () => {
    const { grids } = buildMonthGrids(options, events, "2026-07-15");
    for (const g of grids) for (const w of g.weeks) expect(w.length).toBe(7);
  });
});
