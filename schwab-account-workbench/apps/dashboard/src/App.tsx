import { useMemo } from "react";
import { loadPortfolio } from "./data/load.ts";
import { Overview } from "./components/Overview.tsx";
import { AccountDashboard } from "./components/AccountDashboard.tsx";
import { Calendar } from "./components/Calendar.tsx";
import { ExternalDataPanel } from "./components/ExternalDataPanel.tsx";
import { MonthlyChart } from "./components/MonthlyChart.tsx";
import { Workspace } from "./components/Workspace.tsx";

export function App() {
  // Data is bundled at build time (see src/data/load.ts), so this is synchronous.
  const data = useMemo(() => loadPortfolio(), []);

  return (
    <main className="mx-auto w-[min(1480px,calc(100vw-32px))] py-7">
      <header className="flex items-end justify-between gap-5 border-b-2 border-ink pb-4">
        <div>
          <p className="mb-1.5 text-xs font-black uppercase tracking-[0.12em] text-muted">Schwab Trader API + History CSV</p>
          <h1 className="font-serif text-5xl leading-none md:text-7xl">Account Workbench</h1>
        </div>
        <div className="grid justify-items-end gap-1.5 text-sm font-bold text-muted">
          <span>{data.meta.source} · {data.meta.date}</span>
          <span>{data.legacyTransactions.length.toLocaleString()} history rows</span>
        </div>
      </header>

      <div className="mt-5">
        <Overview data={data} />
        <AccountDashboard data={data} />
        <ExternalDataPanel data={data} />
        <section className="mb-4 grid gap-3">
          <Calendar optionRisk={data.optionRisk} events={data.events} snapshotDate={data.meta.date} />
          <div className="grid gap-3 lg:grid-cols-2">
            <MonthlyChart transactions={data.legacyTransactions} />
          </div>
        </section>
        <Workspace data={data} />
      </div>
    </main>
  );
}
