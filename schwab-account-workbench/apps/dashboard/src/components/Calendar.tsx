import { useMemo } from "react";
import type { OptionRisk, PortfolioEvent } from "../types.ts";
import { buildMonthGrids, WEEKDAY_LABELS, type DayCell, type Urgency } from "../calendar.ts";
import { currency } from "../format.ts";
import { Panel, PanelHead } from "./ui.tsx";

const URGENCY_CELL: Record<Urgency, string> = {
  urgent: "border-red/60 bg-red/5",
  soon: "border-amber/60 bg-amber/5",
  later: "border-cyan/50 bg-cyan/5",
  unknown: "border-rule",
};

// event_type -> label + dot color + short glyph
const EVENT_STYLE: Record<string, { dot: string; text: string; glyph: string; label: string }> = {
  dividend_ex: { dot: "bg-green", text: "text-green", glyph: "◇", label: "Ex-div" },
  dividend_pay: { dot: "bg-cyan", text: "text-cyan", glyph: "$", label: "Div pay" },
  earnings: { dot: "bg-violet", text: "text-violet", glyph: "★", label: "Earnings" },
};

function eventStyle(type: string) {
  return EVENT_STYLE[type] ?? { dot: "bg-muted", text: "text-muted", glyph: "•", label: type };
}

function Cell({ cell }: { cell: DayCell }) {
  if (!cell.inMonth) return <div className="min-h-[68px] rounded-sm bg-transparent" />;
  const hasOptions = cell.entries.length > 0;
  const hasEvents = cell.events.length > 0;
  const marked = hasOptions || hasEvents;
  return (
    <div
      className={`min-h-[68px] rounded-sm border p-1.5 ${hasOptions ? URGENCY_CELL[cell.urgency] : marked ? "border-rule bg-[#fffdf8]" : "border-rule/50 bg-[#fffdf8]"}`}
    >
      <div className="flex items-center justify-between">
        <span className={`text-[11px] font-black ${marked ? "text-ink" : "text-muted"}`}>{cell.day}</span>
        <span className="flex gap-0.5">
          {hasOptions ? <span className={`h-2 w-2 rounded-full ${cell.urgency === "urgent" ? "bg-red" : cell.urgency === "soon" ? "bg-amber" : "bg-cyan"}`} /> : null}
          {[...new Set(cell.events.map((e) => e.event_type))].map((t) => (
            <span key={t} className={`h-2 w-2 rounded-full ${eventStyle(t).dot}`} />
          ))}
        </span>
      </div>

      {cell.entries.map((e, i) => (
        <div key={`opt-${i}`} className="mt-1 leading-tight">
          <div className="truncate text-[11px] font-extrabold text-ink">
            {e.risk.underlying} {e.risk.strike_num ?? ""}
            {String(e.risk.put_call || "").slice(0, 1)}
          </div>
          <div className="text-[10px] font-bold uppercase text-muted">
            {e.isShort ? "Short" : "Long"} ×{e.contracts}
            {e.risk.assignment_notional_num ? ` · ${currency(e.risk.assignment_notional_num)}` : ""}
          </div>
        </div>
      ))}

      {cell.events.map((ev, i) => {
        const st = eventStyle(ev.event_type);
        return (
          <div key={`ev-${i}`} className="mt-1 leading-tight" title={ev.detail}>
            <div className={`truncate text-[11px] font-extrabold ${st.text}`}>
              {st.glyph} {ev.symbol}
            </div>
            <div className="truncate text-[10px] font-bold uppercase text-muted">{st.label}</div>
          </div>
        );
      })}
    </div>
  );
}

export function Calendar({
  optionRisk,
  events,
  snapshotDate,
}: {
  optionRisk: OptionRisk[];
  events: PortfolioEvent[];
  snapshotDate: string;
}) {
  const { grids, undated } = useMemo(
    () => buildMonthGrids(optionRisk, events, snapshotDate),
    [optionRisk, events, snapshotDate],
  );

  const dayCount = grids.reduce(
    (sum, g) => sum + g.weeks.flat().filter((c) => c.entries.length || c.events.length).length,
    0,
  );

  return (
    <Panel className="col-span-full">
      <PanelHead
        label="Upcoming Calendar"
        tip="月历标注：期权到期（红≤7天/橙≤21天/青更远，含指派名义金额）、除息日 ◇、派息日 $、财报 ★（分析师估算日，非交易所确认，临近会调整）。"
        value={dayCount ? `${dayCount} days · ${grids.length} month${grids.length > 1 ? "s" : ""}` : "No events"}
      />

      {grids.length === 0 ? (
        <div className="p-4 font-extrabold text-muted">No upcoming events.</div>
      ) : (
        <div className="grid gap-4 lg:grid-cols-2 xl:grid-cols-3">
          {grids.map((grid) => (
            <div key={grid.label} className="border border-rule bg-[#fffdf8] p-3">
              <div className="mb-2 font-serif text-lg">{grid.label}</div>
              <div className="grid grid-cols-7 gap-1">
                {WEEKDAY_LABELS.map((w) => (
                  <div key={w} className="pb-1 text-center text-[10px] font-black uppercase tracking-wide text-muted">
                    {w}
                  </div>
                ))}
                {grid.weeks.flat().map((cell, i) => (
                  <Cell key={i} cell={cell} />
                ))}
              </div>
            </div>
          ))}
        </div>
      )}

      <div className="mt-3 flex flex-wrap gap-x-4 gap-y-1 text-[11px] font-extrabold uppercase text-muted">
        <span className="flex items-center gap-1.5"><i className="h-2 w-2 rounded-full bg-red" />期权 ≤7天</span>
        <span className="flex items-center gap-1.5"><i className="h-2 w-2 rounded-full bg-amber" />≤21天</span>
        <span className="flex items-center gap-1.5"><i className="h-2 w-2 rounded-full bg-cyan" />更远</span>
        <span className="flex items-center gap-1.5"><i className="h-2 w-2 rounded-full bg-green" />◇ 除息</span>
        <span className="flex items-center gap-1.5"><i className="h-2 w-2 rounded-full bg-cyan" />$ 派息</span>
        <span className="flex items-center gap-1.5"><i className="h-2 w-2 rounded-full bg-violet" />★ 财报(估)</span>
      </div>

      {undated.length ? (
        <div className="mt-2 text-xs font-black text-red">
          {undated.length} option positions need an expiration date
        </div>
      ) : null}
    </Panel>
  );
}
