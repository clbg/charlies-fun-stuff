import { useMemo } from "react";
import type { EChartsOption } from "echarts";
import type { LegacyTx } from "../types.ts";
import { cumulativeCash } from "../metrics.ts";
import { currency, moneyAxis, signClass } from "../format.ts";
import { Chart, chartTextStyle } from "./Chart.tsx";

export function CashChart({ rows }: { rows: LegacyTx[] }) {
  const points = useMemo(() => cumulativeCash(rows), [rows]);
  const net = points.length ? points[points.length - 1].cumulative : 0;

  const option = useMemo<EChartsOption>(() => {
    if (!points.length) {
      return {
        backgroundColor: "#2a2822",
        title: { text: "No transaction history for this symbol", left: "center", top: "middle", textStyle: chartTextStyle("rgba(244,239,228,.72)") },
      };
    }
    const zoom = points.length > 35;
    return {
      animation: false,
      backgroundColor: "#2a2822",
      tooltip: {
        trigger: "axis",
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        formatter: (items: any) => {
          const p = points[items[0].dataIndex];
          const dir = p.flow >= 0 ? "现金流入" : "现金流出";
          return `${p.date} · ${p.action}<br>${p.symbol}<br>本笔 ${dir} ${currency(p.flow)}<br>累计净现金 ${currency(p.cumulative)}`;
        },
      },
      dataZoom: zoom
        ? [{ type: "inside" }, { type: "slider", height: 18, bottom: 8, textStyle: chartTextStyle("#f4efe4") }]
        : [],
      grid: { left: 58, right: 24, top: 28, bottom: zoom ? 42 : 24 },
      xAxis: {
        type: "category",
        data: points.map((p) => p.date),
        axisLabel: chartTextStyle("rgba(244,239,228,.72)"),
        axisLine: { lineStyle: { color: "rgba(244,239,228,.22)" } },
      },
      yAxis: {
        type: "value",
        name: "累计净现金 (非收益)",
        nameTextStyle: chartTextStyle("rgba(244,239,228,.6)"),
        axisLabel: { formatter: moneyAxis, ...chartTextStyle("rgba(244,239,228,.72)") },
        splitLine: { lineStyle: { color: "rgba(244,239,228,.14)" } },
      },
      series: [
        {
          name: "Cumulative cash flow",
          type: "line",
          showSymbol: false,
          data: points.map((p) => p.cumulative),
          lineStyle: { width: 3, color: "#d8a21b" },
          areaStyle: { color: "rgba(216,162,27,.12)" },
          markLine: {
            silent: true,
            symbol: "none",
            lineStyle: { color: "rgba(244,239,228,.5)", type: "dashed", width: 1 },
            label: { formatter: "$0 · 净投入/回收分界", color: "rgba(244,239,228,.7)", position: "insideEndTop" },
            data: [{ yAxis: 0 }],
          },
        },
        {
          name: "Operations",
          type: "scatter",
          symbolSize: 9,
          data: points.map((p) => ({
            value: p.cumulative,
            itemStyle: { color: p.side === "buy" ? "#be3b28" : p.side === "sell" ? "#0a8f5a" : "#d8a21b" },
          })),
        },
      ],
    };
  }, [points]);

  return (
    <div className="mb-2">
      <div className="mb-2 flex items-baseline justify-between">
        <span className="inline-flex items-center text-xs font-black uppercase tracking-[0.08em] text-muted">
          Cumulative Net Cash (In/Out)
        </span>
        <strong className={`tabular text-[13px] font-black ${points.length ? signClass(net) : "text-muted"}`}>
          {points.length ? `${currency(net)} net ${net >= 0 ? "recovered" : "invested"}` : "No cash-flow history"}
        </strong>
      </div>
      <div className="rounded-md bg-panel-strong p-3">
        <Chart option={option} height={260} />
      </div>
    </div>
  );
}
