import { useMemo, useState } from "react";
import type { PortfolioData } from "../types.ts";
import { quoteMap } from "../metrics.ts";
import { allSymbols, groupPositions, legacyRowsFor, quoteFor } from "../selectors.ts";
import { currency, signClass } from "../format.ts";
import { PriceChart } from "./PriceChart.tsx";
import { CashChart } from "./CashChart.tsx";
import { Chip } from "./ui.tsx";

export function Workspace({ data }: { data: PortfolioData }) {
  const qmap = useMemo(() => quoteMap(data.quotes), [data.quotes]);
  const symbols = useMemo(() => {
    return allSymbols(data)
      .map((symbol) => {
        const pos = groupPositions(data, symbol, qmap);
        const legacy = legacyRowsFor(data, symbol);
        const quote = quoteFor(data, symbol);
        const label = quote?.description || pos.rows[0]?.description || legacy[0]?.description || symbol;
        return { symbol, label, pos, legacy, isCurrent: pos.rows.length > 0 };
      })
      .sort((a, b) => Math.abs(b.pos.marketValue) - Math.abs(a.pos.marketValue));
  }, [data, qmap]);

  const [selected, setSelected] = useState<string | null>(symbols[0]?.symbol ?? null);
  const active = symbols.find((s) => s.symbol === selected) ?? symbols[0] ?? null;
  const rows = active ? legacyRowsFor(data, active.symbol) : [];
  const pos = active?.pos;
  const quote = active ? quoteFor(data, active.symbol) : undefined;
  const net = rows.reduce((s, r) => s + (r.cash_flow_num ?? 0), 0);
  const optionRisk = active ? data.optionRisk.filter((r) => r.underlying === active.symbol) : [];
  const deltaDollars = optionRisk.reduce((s, r) => s + (r.delta_dollars_num ?? 0), 0);

  return (
    <section className="grid gap-4 lg:grid-cols-[360px_minmax(0,1fr)]">
      <aside className="grid grid-rows-[auto_minmax(0,1fr)] border border-rule bg-[rgba(255,250,240,0.88)] shadow-[0_18px_40px_rgba(40,35,26,0.12)]">
        <div className="flex justify-between border-b border-rule p-3.5 text-xs font-black uppercase text-muted">
          <span>Underlyings</span>
          <span>{symbols.length}</span>
        </div>
        <div className="max-h-[760px] overflow-auto">
          {symbols.map((item) => {
            const cash = item.isCurrent
              ? item.pos.marketValue
              : item.legacy.reduce((s, r) => s + (r.cash_flow_num ?? 0), 0);
            const isActive = item.symbol === active?.symbol;
            return (
              <button
                key={item.symbol}
                onClick={() => setSelected(item.symbol)}
                className={`grid w-full grid-cols-[1fr_auto] gap-2 border-b border-rule p-3.5 text-left ${isActive ? "bg-ink text-[#fff7e8]" : "hover:bg-ink hover:text-[#fff7e8]"}`}
              >
                <span>
                  <span className="block text-base font-black">{item.symbol}</span>
                  <span className="block text-xs opacity-70">
                    {item.isCurrent ? `current · ${item.pos.quantity.toLocaleString()} qty` : `history · ${item.legacy.length} rows`}
                  </span>
                </span>
                <span className={`tabular self-center text-xs font-bold ${isActive ? "" : signClass(cash)}`}>
                  {currency(cash)}
                </span>
              </button>
            );
          })}
        </div>
      </aside>

      <section className="min-w-0 border border-rule bg-[rgba(255,250,240,0.88)] p-4 shadow-[0_18px_40px_rgba(40,35,26,0.12)]">
        <div className="mb-4">
          <p className="text-xs font-black uppercase tracking-widest text-muted">{pos?.rows[0]?.asset_type || "Symbol"}</p>
          <h2 className="font-serif text-3xl">{active ? `${active.symbol} · ${active.label}` : "Portfolio History"}</h2>
        </div>

        <div className="mb-3 grid grid-cols-2 gap-2 md:grid-cols-4 lg:grid-cols-6">
          <Chip label="Current price" value={quote?.last_price_num != null ? currency(quote.last_price_num) : "-"} cls="text-muted" />
          <Chip label="Market value" value={currency(pos?.marketValue)} cls={signClass(pos?.marketValue)} />
          <Chip label="Day P&L" value={currency(pos?.dayPnL)} cls={signClass(pos?.dayPnL)} />
          <Chip label="Open P&L" value={currency(pos?.openPnL)} cls={signClass(pos?.openPnL)} />
          <Chip label="Option risk" value={optionRisk.length ? `${optionRisk.length} open` : "-"} cls={optionRisk.length ? "text-red" : "text-muted"} />
          <Chip label="Delta $" value={currency(deltaDollars)} cls={signClass(deltaDollars)} />
        </div>

        <PriceChart symbol={active?.symbol ?? null} prices={data.prices} rows={rows} />
        <CashChart rows={rows} />

        <div className="mt-2 flex flex-wrap gap-x-4 gap-y-1 text-[11px] font-extrabold uppercase text-muted">
          <span className="flex items-center gap-1.5"><i className="h-2.5 w-2.5 rounded-full bg-red" />Buy / Buy to Close</span>
          <span className="flex items-center gap-1.5"><i className="h-2.5 w-2.5 rounded-full bg-green" />Sell / Sell to Open</span>
          <span className="flex items-center gap-1.5"><i className="h-2.5 w-2.5 rounded-full bg-violet" />◆ Option trade</span>
          <span className="flex items-center gap-1.5">▲ Expired · 📍 Assigned</span>
        </div>

        <div className="mt-3 flex items-center justify-between text-xs font-black uppercase text-muted">
          <span>Transactions</span>
          <span>{rows.length} rows · net {currency(net)}</span>
        </div>
        <div className="mt-2 max-h-[420px] overflow-auto border border-rule bg-[#fffdf8]">
          <table className="w-full border-collapse text-[13px]">
            <thead>
              <tr className="sticky top-0 bg-ink text-[#fff7e8]">
                {["Date", "Action", "Symbol", "Qty", "Price", "Cash Flow"].map((h) => (
                  <th key={h} className="p-2 text-left text-[11px] uppercase">{h}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {rows
                .slice()
                .sort((a, b) => (b.trade_date || "").localeCompare(a.trade_date || ""))
                .map((r, i) => (
                  <tr key={i} className="border-b border-rule hover:bg-[#fff6df]">
                    <td className="p-2">{r.trade_date}</td>
                    <td className="p-2">{r.action}</td>
                    <td className="p-2">{r.symbol}</td>
                    <td className="tabular p-2 text-right">{r.quantity != null ? String(r.quantity) : ""}</td>
                    <td className="tabular p-2 text-right">{r.price_num != null ? currency(r.price_num) : ""}</td>
                    <td className={`tabular p-2 text-right ${signClass(r.cash_flow_num)}`}>{r.cash_flow_num != null ? currency(r.cash_flow_num) : ""}</td>
                  </tr>
                ))}
            </tbody>
          </table>
        </div>
      </section>
    </section>
  );
}
