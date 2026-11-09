/** Domain-agnostic derivations shared by the expense widgets (ratios of values the caller already has). */

export interface TrendBar { key: string; label: string; value: number; valueText: string; heightPct: number; inProgress: boolean; }

/** Share of `part` in `total`, 0-100; 0 when total is not positive. */
export function sharePercent(part: number, total: number): number {
  return total > 0 && Number.isFinite(part) ? (part / total) * 100 : 0;
}

const PCT = new Intl.NumberFormat('es-MX', { maximumFractionDigits: 1 });
export function formatPercent(value: number | null | undefined): string {
  return value === null || value === undefined || !Number.isFinite(value) ? '—' : `${PCT.format(value)}%`;
}

/** Delta vs. the previous period in percent; null when there is no base to compare with. */
export function deltaPercent(current: number, previous: number | null | undefined): number | null {
  if (previous === null || previous === undefined || !Number.isFinite(previous) || previous <= 0 || !Number.isFinite(current)) return null;
  return ((current - previous) / previous) * 100;
}

export function formatDelta(delta: number | null): string {
  if (delta === null) return '';
  const rounded = Math.round(delta * 10) / 10;
  return `${rounded > 0 ? '+' : rounded < 0 ? '−' : ''}${PCT.format(Math.abs(rounded))}%`;
}

