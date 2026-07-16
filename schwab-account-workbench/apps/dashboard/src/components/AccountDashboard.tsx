import { useMemo } from "react";
import type { PortfolioData } from "../types.ts";
import { positionDayPnl, quoteMap } from "../metrics.ts";
import { accountValue, categoryFor, longPositions, quoteFor } from "../selectors.ts";
import { currency, pct, signClass } from "../format.ts";
import { Panel, PanelHead, Chip } from "./ui.tsx";

export function AccountDashboard({ data }: { data: PortfolioData }) {
  const qmap = useMemo(() => quoteMap(data.quotes), [data.quotes]);
  const acct = data.accounts[0] ?? {};
  const total = accountValue(data);
  const longs = longPositions(data);
  const longValue = acct.long_market_value_num ?? longs.reduce((s, r) => s + (r.market_value_num ?? 0), 0);
  const shortOptions = acct.short_option_market_value_num ??
    data.positions.filter((r) => r.asset_type === "OPTION").reduce((s, r) => s + (r.market_value_num ?? 0), 0);
  const cash = acct.cash_balance_num ?? 0;

  // Allocation by category.
  const catTotals = new Map<string, number>();
  longs.forEach((r) => catTotals.set(categoryFor(r), (catTotals.get(categoryFor(r)) || 0) + (r.market_value_num ?? 0)));
  if (cash) catTotals.set("Cash / collateral", (catTotals.get("Cash / collateral") || 0) + cash);
  const allocation = [...catTotals.entries()].sort((a, b) => Math.abs(b[1]) - Math.abs(a[1]));

  const weighted = longs
    .filter((r) => r.market_value_num)
    .map((r) => ({ ...r, weight: total ? (r.market_value_num ?? 0) / total * 100 : 0 }))
    .sort((a, b) => b.weight - a.weight);
  const top3 = weighted.slice(0, 3).reduce((s, r) => s + r.weight, 0);
  const assignment = data.optionRisk.reduce((s, r) => s + (r.assignment_notional_num ?? 0), 0);
  const deltaDollars = data.optionRisk.reduce((s, r) => s + (r.delta_dollars_num ?? 0), 0);

  const positionsByValue = [...data.positions].sort(
    (a, b) => Math.abs(b.market_value_num ?? 0) - Math.abs(a.market_value_num ?? 0),
  );
  const optionsByDte = [...data.optionRisk].sort(
    (a, b) => (a.days_to_expiration_num ?? 999) - (b.days_to_expiration_num ?? 999),
  );

  return (
    <section className="mb-4 grid gap-3 xl:grid-cols-[minmax(340px,0.9fr)_minmax(360px,1fr)_minmax(320px,0.9fr)]">
      <Panel>
        <PanelHead label="Account State" value="Schwab Trader API" />
        <div className="grid grid-cols-2 gap-2">
          <Chip label="Account value" tip="Schwab liquidationValue。" value={currency(total)} cls={signClass(total)} />
          <Chip label="Cash" value={currency(cash)} cls="text-muted" />
          <Chip label="Buying power" value={currency(acct.buying_power_num ?? 0)} cls="text-muted" />
          <Chip label="Long holdings" value={currency(longValue)} cls="text-muted" />
          <Chip label="Short options" value={currency(shortOptions)} cls={signClass(shortOptions)} />
          <Chip label="Maintenance" value={currency(acct.maintenance_requirement_num ?? 0)} cls="text-muted" />
        </div>
      </Panel>

      <Panel>
        <PanelHead label="Allocation" value="Current" />
        <div className="grid gap-2.5">
          {allocation.map(([label, val]) => {
            const w = total ? (val / total) * 100 : 0;
            return (
              <div key={label} className="grid gap-1">
                <div className="flex justify-between text-xs font-black">
                  <span>{label}</span>
                  <strong>{pct(w)}</strong>
                </div>
                <div className="h-2.5 overflow-hidden border border-rule bg-[#ece1cc]">
                  <i className="block h-full bg-gradient-to-r from-cyan to-amber" style={{ width: `${Math.max(1, Math.min(Math.abs(w), 100))}%` }} />
                </div>
              </div>
            );
          })}
        </div>
      </Panel>

      <Panel>
        <PanelHead label="Risk & Concentration" value="Live holdings" />
        <div className="grid grid-cols-2 gap-2">
          <Chip label="Largest holding" value={weighted[0] ? `${weighted[0].underlying} ${pct(weighted[0].weight)}` : "-"} cls={(weighted[0]?.weight ?? 0) > 40 ? "text-red" : "text-muted"} />
          <Chip label="Top 3" value={pct(top3)} cls={top3 > 60 ? "text-red" : "text-muted"} />
          <Chip label="Cash buffer" value={pct(total ? (cash / total) * 100 : 0)} cls={cash / Math.max(total, 1) > 0.15 ? "text-green" : "text-muted"} />
          <Chip label="Assignment" tip="卖出期权若被行权的名义金额，strike×100×contracts 粗算。" value={currency(assignment)} cls={assignment / Math.max(total, 1) > 0.5 ? "text-red" : "text-muted"} />
          <Chip label="Delta dollars" tip="期权 delta × 净合约 × 100 × 标的价。空头方向已修正。" value={currency(deltaDollars)} cls={signClass(deltaDollars)} />
        </div>
      </Panel>

      <Panel className="xl:col-span-2">
        <PanelHead label="Current Holdings" value={`${data.positions.length} positions · ${currency(total)}`} />
        <div className="max-h-[420px] overflow-auto border border-rule bg-[#fffdf8]">
          <table className="w-full border-collapse text-xs">
            <thead>
              <tr className="sticky top-0 bg-ink text-[#fff7e8]">
                {["Ticker", "Type", "Qty", "Value", "Quote", "Day P&L", "Open P&L"].map((h) => (
                  <th key={h} className="p-2 text-left text-[11px] uppercase">{h}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {positionsByValue.map((row, i) => {
                const q = quoteFor(data, row.underlying || row.symbol);
                const price = q?.last_price_num ?? q?.mark_num ?? row.average_price_num;
                const day = positionDayPnl(row, qmap);
                return (
                  <tr key={i} className="border-b border-rule hover:bg-[#fff6df]">
                    <td className="p-2"><strong>{row.symbol}</strong></td>
                    <td className="p-2">{row.asset_type}{row.put_call ? ` · ${row.put_call}` : ""}</td>
                    <td className="tabular p-2 text-right">{row.net_quantity_num?.toLocaleString() ?? "-"}</td>
                    <td className="tabular p-2 text-right">{currency(row.market_value_num)}</td>
                    <td className="tabular p-2 text-right">{price == null ? "-" : currency(price)}</td>
                    <td className={`tabular p-2 text-right ${signClass(day)}`}>{currency(day)}</td>
                    <td className={`tabular p-2 text-right ${signClass(row.long_open_profit_loss_num)}`}>{currency(row.long_open_profit_loss_num)}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </Panel>

      <Panel>
        <PanelHead label="Options Book" value={`${data.optionRisk.length} open · ${currency(shortOptions)}`} />
        <div className="max-h-[300px] overflow-auto border border-rule bg-[#fffdf8]">
          {data.optionRisk.length ? (
            <table className="w-full border-collapse text-xs">
              <thead>
                <tr className="sticky top-0 bg-ink text-[#fff7e8]">
                  {["Contract", "DTE", "IV", "Delta", "Theta", "Assign"].map((h) => (
                    <th key={h} className="p-2 text-left text-[11px] uppercase">{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {optionsByDte.map((row, i) => (
                  <tr key={i} className="border-b border-rule hover:bg-[#fff6df]">
                    <td className="p-2"><strong>{row.underlying} {row.strike_num ?? ""} {row.put_call}</strong><br /><small>{row.expiration}</small></td>
                    <td className="p-2">{row.days_to_expiration_num ?? "-"}</td>
                    <td className="p-2">{row.iv_num != null ? pct(row.iv_num) : "-"}</td>
                    <td className="p-2">{row.delta_num ?? "-"}</td>
                    <td className="p-2">{row.theta_num ?? "-"}</td>
                    <td className="tabular p-2 text-right">{currency(row.assignment_notional_num)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          ) : (
            <div className="p-4 font-extrabold text-muted">No open option risk rows. Re-run API refresh with option chains enabled for Greeks.</div>
          )}
        </div>
      </Panel>
    </section>
  );
}
