export function num(value: unknown): number | null {
  if (value === "" || value == null) return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

export function currency(value: unknown): string {
  const n = num(value) ?? 0;
  const formatted = Math.abs(n).toLocaleString("en-US", {
    style: "currency",
    currency: "USD",
  });
  return n < 0 ? `-${formatted}` : formatted;
}

export function pct(value: unknown): string {
  return `${(num(value) ?? 0).toLocaleString("en-US", { maximumFractionDigits: 2 })}%`;
}

export function fmtQty(value: unknown): string {
  const n = num(value);
  return n == null ? "-" : n.toLocaleString("en-US", { maximumFractionDigits: 4 });
}

export function moneyAxis(value: number): string {
  const n = Number(value) || 0;
  const abs = Math.abs(n);
  if (abs >= 1_000_000) return `$${(n / 1_000_000).toFixed(1)}M`;
  if (abs >= 1_000) return `$${(n / 1_000).toFixed(0)}k`;
  return `$${n.toFixed(0)}`;
}

export type Sign = "positive" | "negative" | "neutral";

export function signOf(value: unknown): Sign {
  const n = num(value) ?? 0;
  return n > 0 ? "positive" : n < 0 ? "negative" : "neutral";
}

/** Tailwind text color class for a signed value. */
export function signClass(value: unknown): string {
  const s = signOf(value);
  return s === "positive" ? "text-green" : s === "negative" ? "text-red" : "text-muted";
}
