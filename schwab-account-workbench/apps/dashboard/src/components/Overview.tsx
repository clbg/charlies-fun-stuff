import { useMemo } from "react";
import type { PortfolioData } from "../types.ts";
import { accountDayPnl, quoteMap } from "../metrics.ts";
import { accountValue } from "../selectors.ts";
import { currency, signClass } from "../format.ts";
import { Metric } from "./ui.tsx";

export function Overview({ data }: { data: PortfolioData }) {
  const value = accountValue(data);
  const qmap = useMemo(() => quoteMap(data.quotes), [data.quotes]);
  const openPnL = data.positions.reduce((s, r) => s + (r.long_open_profit_loss_num ?? 0), 0);
  const dayPnL = accountDayPnl(data.positions, qmap);

  return (
    <section className="mb-4 grid grid-cols-2 gap-3 lg:grid-cols-4">
      <Metric label="History Rows" tip="完整历史交易 CSV 的总行数。衡量历史数据量，不代表当前持仓数量。">
        {data.legacyTransactions.length.toLocaleString()}
      </Metric>
      <Metric label="Account Value" tip="账户当前总价值，来自最新 Schwab Trader API balances。">
        {currency(value)}
      </Metric>
      <Metric label="Unrealized P&L" tip="当前持仓相对成本的未实现盈亏，不含已卖出仓位的 realized P&L。">
        <span className={signClass(openPnL)}>{currency(openPnL)}</span>
      </Metric>
      <Metric label="Day P&L" tip="账户当日盈亏合计。有实时报价的非期权持仓按 净持仓 × 报价当日涨跌额 重算（规避 BOXX 等类现金 ETF 的 currentDayProfitLoss 脏值），无报价时回退 API 字段。">
        <span className={signClass(dayPnL)}>{currency(dayPnL)}</span>
      </Metric>
    </section>
  );
}
