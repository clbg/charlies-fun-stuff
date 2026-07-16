import { useMemo } from "react";
import type { EChartsOption } from "echarts";
import type { LegacyTx, PriceRow } from "../types.ts";
import { projectOptionEvents, sortPricesFor, stockExecutions } from "../metrics.ts";
import { currency } from "../format.ts";
import { Chart, chartTextStyle } from "./Chart.tsx";

const STATUS_STYLE = {
  TRADE: { symbol: "diamond", size: 13, color: "#6d4bd8", name: "Option trade" },
  EXPIRED: { symbol: "triangle", size: 12, color: "#6b675d", name: "Option expired" },
  ASSIGNED: { symbol: "pin", size: 16, color: "#d8a21b", name: "Option assigned" },
} as const;

export function PriceChart({
  symbol,
  prices,
  rows,
}: {
  symbol: string | null;
  prices: PriceRow[];
  rows: LegacyTx[];
}) {
  const { option, meta } = useMemo(() => {
    if (!symbol) return { option: {} as EChartsOption, meta: "No symbol" };
    const sorted = sortPricesFor(symbol, prices);
    if (!sorted.length) {
      return {
        option: {
          title: { text: "No Schwab API daily price history for this symbol", left: 16, top: 16, textStyle: chartTextStyle("#6b675d") },
        } as EChartsOption,
        meta: "No market prices",
      };
    }
    const stock = stockExecutions(rows);
    const events = projectOptionEvents(symbol, rows, sorted);
    const byStatus = (s: keyof typeof STATUS_STYLE) =>
      events
        .filter((e) => e.status === s)
        .map((e) => ({ value: [e.date, e.close], meta: e }));

    const option: EChartsOption = {
      animation: false,
      tooltip: {
        trigger: "item",
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        formatter: (item: any) => {
          const m = item.data?.meta;
          if (m) {
            const prem = m.premium != null ? ` · premium ${currency(m.premium)}` : "";
            const exp = m.expiration ? ` · exp ${m.expiration}` : "";
            return `${m.contract} — ${m.status}${exp}<br>标的价 ${currency(m.close)}${prem}<br><small>${m.action}</small>`;
          }
          const v = Array.isArray(item.value) ? item.value[1] : item.value;
          return `${item.seriesName}: ${currency(v)}`;
        },
      },
      legend: { top: 0, type: "scroll", textStyle: chartTextStyle("#6b675d") },
      grid: { left: 54, right: 24, top: 34, bottom: 58 },
      dataZoom: [
        { type: "inside", filterMode: "none" },
        { type: "slider", height: 20, bottom: 12, filterMode: "none", textStyle: chartTextStyle("#6b675d") },
      ],
      xAxis: { type: "time", axisLabel: chartTextStyle("#6b675d") },
      yAxis: {
        type: "value",
        scale: true,
        axisLabel: { formatter: (v: number) => currency(v).replace(".00", ""), ...chartTextStyle("#6b675d") },
        splitLine: { lineStyle: { color: "rgba(23,22,18,.12)" } },
      },
      series: [
        { name: "Schwab daily close", type: "line", showSymbol: false, data: sorted.map((r) => [r.date, r.close_num]), lineStyle: { width: 2.5, color: "#167c91" } },
        { name: "Buy executions", type: "scatter", symbol: "circle", symbolSize: 9, data: stock.filter((s) => s.side === "buy").map((s) => ({ value: [s.date, s.price] })), itemStyle: { color: "#be3b28" } },
        { name: "Sell executions", type: "scatter", symbol: "circle", symbolSize: 9, data: stock.filter((s) => s.side === "sell").map((s) => ({ value: [s.date, s.price] })), itemStyle: { color: "#0a8f5a" } },
        ...(["TRADE", "EXPIRED", "ASSIGNED"] as const).map((s) => ({
          name: STATUS_STYLE[s].name,
          type: "scatter" as const,
          symbol: STATUS_STYLE[s].symbol,
          symbolSize: STATUS_STYLE[s].size,
          data: byStatus(s),
          itemStyle: { color: STATUS_STYLE[s].color, borderColor: "#fffdf8", borderWidth: 1 },
        })),
      ],
    };
    return { option, meta: `${sorted.length} candles · ${events.length} option events` };
  }, [symbol, prices, rows]);

  return (
    <div className="mb-3 border border-rule bg-[#fffdf8] p-3">
      <div className="mb-2 flex items-baseline justify-between">
        <span className="text-xs font-black uppercase tracking-[0.08em] text-muted">Executions vs Price History</span>
        <strong className="text-[13px] font-black text-ink">{meta}</strong>
      </div>
      <Chart option={option} height={240} />
    </div>
  );
}
