import type { AnalystRating, PortfolioData } from "../types.ts";
import { currency, pct } from "../format.ts";
import { Panel, PanelHead, Chip } from "./ui.tsx";

function statusClass(status: string) {
  if (status === "ok") return "text-green";
  if (status === "partial" || status === "skipped") return "text-amber";
  return "text-red";
}

function ratingScore(r: AnalystRating) {
  return (r.strong_buy_num ?? 0) * 2 + (r.buy_num ?? 0) - (r.sell_num ?? 0) - (r.strong_sell_num ?? 0) * 2;
}

export function ExternalDataPanel({ data }: { data: PortfolioData }) {
  const filings = [...data.secFilings]
    .sort((a, b) => (b.filing_date || "").localeCompare(a.filing_date || ""))
    .slice(0, 10);
  const macro = [...data.macroEvents]
    .sort((a, b) => (a.event_date || "").localeCompare(b.event_date || ""))
    .slice(0, 12);
  const ratings = [...data.analystRatings]
    .sort((a, b) => ratingScore(b) - ratingScore(a))
    .slice(0, 8);
  const news = [...data.newsHeadlines]
    .sort((a, b) => (b.datetime || "").localeCompare(a.datetime || ""))
    .slice(0, 8);
  const btc = data.cryptoPrices.find((r) => r.asset === "bitcoin");

  return (
    <section className="mb-4 grid gap-3 xl:grid-cols-[0.75fr_1.1fr_1.1fr]">
      <Panel>
        <PanelHead
          label="Data Sources"
          tip="每个外部数据源的本次刷新状态。ok 表示成功，partial 表示部分数据可用，skipped 通常是缺少免费 API key 或当前组合不需要该源。"
          value={`${data.sourceStatus.length} sources`}
        />
        <div className="grid grid-cols-2 gap-2">
          {data.sourceStatus.map((row) => (
            <Chip
              key={row.source}
              label={row.source}
              tip={row.detail}
              value={`${row.status}${row.rows_num != null ? ` · ${row.rows_num}` : ""}`}
              cls={statusClass(row.status)}
            />
          ))}
        </div>
      </Panel>

      <Panel>
        <PanelHead label="SEC Filings" tip="SEC EDGAR 最近 10-K/10-Q/8-K/20-F/6-K 元数据。用于知道持仓公司最近披露了什么，不解析全文。" value={`${data.secFilings.length} rows`} />
        <div className="max-h-[300px] overflow-auto border border-rule bg-[#fffdf8]">
          {filings.length ? (
            <table className="w-full border-collapse text-xs">
              <thead>
                <tr className="sticky top-0 bg-ink text-[#fff7e8]">
                  {["Date", "Symbol", "Form", "Description"].map((h) => <th key={h} className="p-2 text-left text-[11px] uppercase">{h}</th>)}
                </tr>
              </thead>
              <tbody>
                {filings.map((row, i) => (
                  <tr key={`${row.symbol}-${row.accession_number}-${i}`} className="border-b border-rule hover:bg-[#fff6df]">
                    <td className="p-2 tabular">{row.filing_date}</td>
                    <td className="p-2 font-black">{row.symbol}</td>
                    <td className="p-2">{row.form}</td>
                    <td className="p-2">{row.description || row.primary_document || row.company_name}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          ) : <div className="p-4 font-extrabold text-muted">No SEC filing rows.</div>}
        </div>
      </Panel>

      <Panel>
        <PanelHead label="Macro + Crypto" tip="宏观事件来自 FRED/FOMC；BTC 参考价来自 CoinGecko，用来辅助观察 IBIT/BTCO。" value={`${data.macroEvents.length} macro · ${data.cryptoPrices.length} crypto`} />
        <div className="grid gap-2">
          {btc ? (
            <div className="grid grid-cols-3 gap-2">
              <Chip label="BTC price" value={currency(btc.price_usd_num)} cls="text-ink" />
              <Chip label="24h" value={pct(btc.change_24h_pct_num)} cls={(btc.change_24h_pct_num ?? 0) >= 0 ? "text-green" : "text-red"} />
              <Chip label="Mkt cap" value={currency(btc.market_cap_usd_num)} cls="text-muted" />
            </div>
          ) : null}
          <div className="max-h-[218px] overflow-auto border border-rule bg-[#fffdf8]">
            {macro.length ? macro.map((row, i) => (
              <div key={`${row.event_date}-${row.detail}-${i}`} className="border-b border-rule p-2 text-xs">
                <div className="flex justify-between gap-2">
                  <strong>{row.event_date}</strong>
                  <span className={row.importance === "high" ? "text-red" : "text-muted"}>{row.source}</span>
                </div>
                <div className="font-extrabold text-muted">{row.detail}</div>
              </div>
            )) : <div className="p-4 font-extrabold text-muted">No macro rows.</div>}
          </div>
        </div>
      </Panel>

      <Panel className="xl:col-span-3">
        <PanelHead label="News + Ratings" tip="Finnhub 免费 key 可提供新闻标题和分析师评级分布。没有 key 时这里会显示为空，但主账户数据不受影响。" value={`${data.analystRatings.length} ratings · ${data.newsHeadlines.length} headlines`} />
        <div className="grid gap-3 lg:grid-cols-2">
          <div className="border border-rule bg-[#fffdf8]">
            {ratings.length ? ratings.map((row) => (
              <div key={row.symbol} className="grid grid-cols-[80px_1fr] gap-2 border-b border-rule p-2 text-xs">
                <strong>{row.symbol}</strong>
                <span className="font-extrabold text-muted">
                  Strong buy {row.strong_buy_num ?? 0} · Buy {row.buy_num ?? 0} · Hold {row.hold_num ?? 0} · Sell {(row.sell_num ?? 0) + (row.strong_sell_num ?? 0)}
                </span>
              </div>
            )) : <div className="p-4 font-extrabold text-muted">No Finnhub ratings. Add a Finnhub key to enable.</div>}
          </div>
          <div className="max-h-[260px] overflow-auto border border-rule bg-[#fffdf8]">
            {news.length ? news.map((row, i) => (
              <a key={`${row.symbol}-${i}`} href={row.url} target="_blank" rel="noreferrer" className="block border-b border-rule p-2 text-xs hover:bg-[#fff6df]">
                <strong>{row.symbol}</strong>
                <span className="ml-2 text-muted">{row.source}</span>
                <div className="mt-1 font-extrabold text-ink">{row.headline}</div>
              </a>
            )) : <div className="p-4 font-extrabold text-muted">No Finnhub headlines. Add a Finnhub key to enable.</div>}
          </div>
        </div>
      </Panel>
    </section>
  );
}
