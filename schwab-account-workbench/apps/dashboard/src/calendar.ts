// Month-grid calendar model for option expirations. Pure date math (UTC only,
// to avoid timezone day-shifts) that the Calendar component renders.

import type { OptionRisk, PortfolioEvent } from "./types.ts";

const DAY_MS = 24 * 60 * 60 * 1000;

export interface ParsedDate {
  epoch: number;
  year: number;
  month: number; // 0-based
  day: number;
  value: string; // original YYYY-MM-DD
}

export function parseISODate(value: string | undefined): ParsedDate | null {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(value || ""));
  if (!match) return null;
  const [, y, m, d] = match.map(Number);
  const epoch = Date.UTC(y, m - 1, d);
  const dt = new Date(epoch);
  if (dt.getUTCFullYear() !== y || dt.getUTCMonth() !== m - 1 || dt.getUTCDate() !== d) {
    return null;
  }
  return { epoch, year: y, month: m - 1, day: d, value: String(value) };
}

export function daysBetween(fromISO: string, toISO: string): number | null {
  const a = parseISODate(fromISO);
  const b = parseISODate(toISO);
  if (!a || !b) return null;
  return Math.round((b.epoch - a.epoch) / DAY_MS);
}

export type Urgency = "urgent" | "soon" | "later" | "unknown";

export function urgencyOf(dte: number | null): Urgency {
  if (dte == null) return "unknown";
  if (dte <= 7) return "urgent";
  if (dte <= 21) return "soon";
  return "later";
}

export interface CalendarEntry {
  risk: OptionRisk;
  contracts: number;
  isShort: boolean;
}

export interface DayCell {
  date: string | null; // null = padding cell
  day: number | null;
  inMonth: boolean;
  dte: number | null;
  urgency: Urgency;
  entries: CalendarEntry[]; // option expirations
  events: PortfolioEvent[]; // dividends, earnings, etc.
  assignment: number;
}

export interface MonthGrid {
  year: number;
  month: number; // 0-based
  label: string; // "July 2026"
  weeks: DayCell[][]; // rows of 7 (Sun..Sat)
}

const MONTH_NAMES = [
  "January", "February", "March", "April", "May", "June",
  "July", "August", "September", "October", "November", "December",
];

export function contractCount(risk: OptionRisk): number {
  const s = Math.abs(risk.short_quantity_num ?? 0);
  const l = Math.abs(risk.long_quantity_num ?? 0);
  return s + l;
}

/**
 * Lay out option expirations AND portfolio events (dividends, earnings) on month
 * grids. `snapshotISO` anchors the "days to expiration" countdown. Returns one
 * grid per month that contains at least one dated item, chronologically.
 */
export function buildMonthGrids(
  risks: OptionRisk[],
  events: PortfolioEvent[],
  snapshotISO: string,
): { grids: MonthGrid[]; undated: OptionRisk[] } {
  const entriesByDate = new Map<string, CalendarEntry[]>();
  const eventsByDate = new Map<string, PortfolioEvent[]>();
  const undated: OptionRisk[] = [];

  for (const risk of risks) {
    const contracts = contractCount(risk);
    if (contracts <= 0) continue;
    const parsed = parseISODate(risk.expiration);
    if (!parsed) {
      undated.push(risk);
      continue;
    }
    const entry: CalendarEntry = { risk, contracts, isShort: (risk.short_quantity_num ?? 0) > 0 };
    const list = entriesByDate.get(parsed.value);
    if (list) list.push(entry);
    else entriesByDate.set(parsed.value, [entry]);
  }

  for (const event of events) {
    const parsed = parseISODate(event.event_date);
    if (!parsed) continue;
    const list = eventsByDate.get(parsed.value);
    if (list) list.push(event);
    else eventsByDate.set(parsed.value, [event]);
  }

  // Which (year, month) pairs need a grid — union of both sources.
  const monthKeys = new Set<string>();
  for (const dateStr of [...entriesByDate.keys(), ...eventsByDate.keys()]) {
    const p = parseISODate(dateStr)!;
    monthKeys.add(`${p.year}-${p.month}`);
  }

  const grids: MonthGrid[] = [...monthKeys]
    .map((key) => key.split("-").map(Number) as [number, number])
    .sort((a, b) => a[0] - b[0] || a[1] - b[1])
    .map(([year, month]) => buildGrid(year, month, entriesByDate, eventsByDate, snapshotISO));

  return { grids, undated };
}

function buildGrid(
  year: number,
  month: number,
  entriesByDate: Map<string, CalendarEntry[]>,
  eventsByDate: Map<string, PortfolioEvent[]>,
  snapshotISO: string,
): MonthGrid {
  const firstEpoch = Date.UTC(year, month, 1);
  const firstWeekday = new Date(firstEpoch).getUTCDay(); // 0=Sun
  const daysInMonth = new Date(Date.UTC(year, month + 1, 0)).getUTCDate();

  const cells: DayCell[] = [];
  for (let i = 0; i < firstWeekday; i++) cells.push(emptyCell());
  for (let day = 1; day <= daysInMonth; day++) {
    const iso = `${year}-${String(month + 1).padStart(2, "0")}-${String(day).padStart(2, "0")}`;
    const entries = entriesByDate.get(iso) || [];
    const events = eventsByDate.get(iso) || [];
    const dte = entries.length ? daysBetween(snapshotISO, iso) : null;
    const assignment = entries.reduce((sum, e) => sum + (e.risk.assignment_notional_num ?? 0), 0);
    cells.push({
      date: iso,
      day,
      inMonth: true,
      dte,
      urgency: entries.length ? urgencyOf(dte) : "unknown",
      entries,
      events,
      assignment,
    });
  }
  while (cells.length % 7 !== 0) cells.push(emptyCell());

  const weeks: DayCell[][] = [];
  for (let i = 0; i < cells.length; i += 7) weeks.push(cells.slice(i, i + 7));

  return { year, month, label: `${MONTH_NAMES[month]} ${year}`, weeks };
}

function emptyCell(): DayCell {
  return { date: null, day: null, inMonth: false, dte: null, urgency: "unknown", entries: [], events: [], assignment: 0 };
}

export const WEEKDAY_LABELS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
