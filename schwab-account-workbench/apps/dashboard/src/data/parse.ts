import { num } from "../format.ts";

const NON_NUMERIC_KEYS = new Set([
  "symbol", "underlying", "description", "type", "status", "asset_type",
  "put_call", "expiration", "option_expiration", "snapshot_date", "date",
  "time", "instrument_type", "action", "side", "source",
]);

/** RFC-4180-ish CSV parser (quotes, escaped quotes, CRLF). */
export function parseCSV(text: string): Record<string, string>[] {
  const rows: string[][] = [];
  let row: string[] = [];
  let cell = "";
  let quoted = false;
  const src = text || "";
  for (let i = 0; i < src.length; i++) {
    const char = src[i];
    const next = src[i + 1];
    if (char === '"' && quoted && next === '"') {
      cell += '"';
      i++;
    } else if (char === '"') {
      quoted = !quoted;
    } else if (char === "," && !quoted) {
      row.push(cell);
      cell = "";
    } else if ((char === "\n" || char === "\r") && !quoted) {
      if (char === "\r" && next === "\n") i++;
      row.push(cell);
      if (row.some((v) => v.length)) rows.push(row);
      row = [];
      cell = "";
    } else {
      cell += char;
    }
  }
  if (cell.length || row.length) {
    row.push(cell);
    rows.push(row);
  }
  const headers = rows.shift() || [];
  return rows.map((values) =>
    Object.fromEntries(headers.map((h, i) => [h, values[i] ?? ""])),
  );
}

/** Add `<col>_num` numeric mirrors to each row for non-textual columns. */
export function withNumericMirrors<T extends Record<string, string>>(
  rows: T[],
): (T & Record<string, unknown>)[] {
  return rows.map((row) => {
    const out: Record<string, unknown> = { ...row };
    for (const key of Object.keys(row)) {
      if (NON_NUMERIC_KEYS.has(key)) continue;
      const parsed = num(row[key]);
      if (parsed != null) out[`${key}_num`] = parsed;
    }
    return out as T & Record<string, unknown>;
  });
}

export function parseTable<T>(csv: string | undefined): T[] {
  if (!csv) return [];
  return withNumericMirrors(parseCSV(csv)) as T[];
}
