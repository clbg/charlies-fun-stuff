import { useMemo } from "react";
import type { EChartsOption } from "echarts";
import type { LegacyTx } from "../types.ts";
import { currency, moneyAxis, signClass } from "../format.ts";
import { Panel, PanelHead } from "./ui.tsx";
import { Chart, chartTextStyle } from "./Chart.tsx";

export function MonthlyChart({ transactions }: { transactions: LegacyTx[] }) {
  const { option, net } = useMemo(() => {
    const grouped = new Map<string, number>();
    transactions.forEach((r) => {
      const key = (r.trade_date || "").slice(0, 7);
      if (!key) return;
      grouped.set(key, (grouped.get(key) || 0) + (r.cash_flow_num ?? 0));
    });
    const entries = [...grouped.entries()].sort((a, b) => a[0].localeCompare(b[0])).slice(-36);
    const values = entries.map(([, v]) => v);
    const zoom = entries.length > 12;
    const option: EChartsOption = {
      animation: false,
      tooltip: { trigger: "axis", valueFormatter: (v) => currency(v as number) },
      grid: { left: 54, right: 18, top: 18, bottom: zoom ? 60 : 42 },
      dataZoom: zoom ? [{ type: "inside" }, { type: "slider", height: 18, bottom: 10, textStyle: chartTextStyle("#6b675d") }] : [],
      xAxis: { type: "category", data: entries.map(([k]) => k), axisLabel: { ...chartTextStyle("#6b675d"), rotate: 35 } },
      yAxis: { type: "value", axisLabel: { formatter: moneyAxis, ...chartTextStyle("#6b675d") }, splitLine: { lineStyle: { color: "rgba(23,22,18,.12)" } } },
      series: [{ type: "bar", barMaxWidth: 18, data: values.map((v) => ({ value: v, itemStyle: { color: v >= 0 ? "#0a8f5a" : "#be3b28" } })) }],
    };
    return { option, net: values.reduce((s, v) => s + v, 0) };
  }, [transactions]);

  return (
    <Panel className="col-span-full lg:col-span-2">
      <PanelHead
        label="Monthly Net Cash Flow"
        tip="每月交易和现金活动的净现金流。负数通常是净买入/出金，正数通常是卖出/入金/收入。"
        value={<span className={signClass(net)}>{currency(net)}</span>}
      />
      <Chart option={option} height={220} />
    </Panel>
  );
}
