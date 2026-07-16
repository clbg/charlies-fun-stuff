import type { ReactNode } from "react";

/** Small "?" tooltip trigger, ported from the original .tip pattern. */
export function Tip({ text }: { text: string }) {
  return (
    <span className="group relative inline-flex items-center">
      <button
        type="button"
        aria-label={text}
        title={text}
        className="ml-1.5 grid h-4 w-4 place-items-center rounded-full border border-current bg-[#fffdf8] text-[10px] font-black text-muted"
      >
        ?
      </button>
    </span>
  );
}

export function PanelHead({ label, tip, value }: { label: string; tip?: string; value?: ReactNode }) {
  return (
    <div className="mb-2.5 flex items-baseline justify-between gap-3">
      <span className="inline-flex items-center text-xs font-black uppercase tracking-[0.08em] text-muted">
        {label}
        {tip ? <Tip text={tip} /> : null}
      </span>
      {value != null ? <strong className="tabular text-[13px] font-black text-ink">{value}</strong> : null}
    </div>
  );
}

export function Panel({
  children,
  className = "",
}: {
  children: ReactNode;
  className?: string;
}) {
  return (
    <article
      className={`min-w-0 border border-rule bg-panel p-3.5 shadow-[0_18px_40px_rgba(40,35,26,0.12)] ${className}`}
    >
      {children}
    </article>
  );
}

export function Metric({ label, tip, children }: { label: string; tip?: string; children: ReactNode }) {
  return (
    <article className="border border-l-[5px] border-rule border-l-ink bg-panel p-4 shadow-[0_18px_40px_rgba(40,35,26,0.12)]">
      <span className="inline-flex items-center text-xs font-black uppercase tracking-[0.08em] text-muted">
        {label}
        {tip ? <Tip text={tip} /> : null}
      </span>
      <strong className="mt-2 block font-serif text-[30px] leading-none">{children}</strong>
    </article>
  );
}

export function Chip({ label, tip, value, cls = "" }: { label: string; tip?: string; value: ReactNode; cls?: string }) {
  return (
    <div className="min-w-0 border border-rule bg-[#fffdf8] p-2.5">
      <span className="block text-[11px] font-extrabold uppercase tracking-[0.05em] text-muted">
        {label}
        {tip ? <Tip text={tip} /> : null}
      </span>
      <strong className={`tabular mt-1 block text-[19px] ${cls}`}>{value}</strong>
    </div>
  );
}
