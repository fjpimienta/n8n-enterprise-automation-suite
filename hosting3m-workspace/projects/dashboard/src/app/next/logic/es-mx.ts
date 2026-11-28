/**
 * es-MX presentation helpers for the `next` UI only (no global LOCALE_ID, by decision).
 * Timezone Armor: date-only values are read from the text of the value ("YYYY-MM-DD"), never via
 * `toISOString()`, and the calendar day is formatted in UTC so it can never shift by zone.
 */

export type ChipKind = 'available' | 'occupied' | 'cleaning' | 'maintenance' | 'reserved';

export const CHIP_LABEL: Record<ChipKind, string> = {
  available: 'Disponible',
  occupied: 'Ocupada',
  cleaning: 'Limpieza',
  maintenance: 'Mantenimiento',
  reserved: 'Llegada hoy'
};

export const PAYMENT_LABEL: Record<string, string> = { paid: 'Pagado', pending: 'Pendiente', partial: 'Parcial' };

/** Spanish label for a payment status; unknown values are shown as "—". */
export function paymentLabel(value: unknown): string {
  return typeof value === 'string' ? (PAYMENT_LABEL[value.toLowerCase()] ?? '—') : '—';
}

const DATE_ONLY = /^(\d{4})-(\d{2})-(\d{2})/;

/** "YYYY-MM-DD" from a gateway value ("2026-11-27T00:00:00.000Z", "2026-11-27 00:00:00", ...) or null. */
export function datePart(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  const m = DATE_ONLY.exec(value.trim());
  return m ? `${m[1]}-${m[2]}-${m[3]}` : null;
}

function utcDate(y: number, m: number, d: number): Date {
  return new Date(Date.UTC(y, m - 1, d));
}

/** Short day and month for a gateway date, e.g. "27 nov". Returns "—" when the value has no date. */
export function formatDayMonth(value: unknown): string {
  const part = datePart(value);
  if (!part) return '—';
  const [y, m, d] = part.split('-').map(Number);
  const text = new Intl.DateTimeFormat('es-MX', { day: 'numeric', month: 'short', timeZone: 'UTC' }).format(utcDate(y, m, d));
  return text.replace(/\./g, '');
}

/** Long date for "today" from the LOCAL calendar fields, e.g. "viernes 27 de noviembre". */
export function formatLongDate(now: Date = new Date()): string {
  return new Intl.DateTimeFormat('es-MX', { weekday: 'long', day: 'numeric', month: 'long', timeZone: 'UTC' })
    .format(utcDate(now.getFullYear(), now.getMonth() + 1, now.getDate()))
    .replace(',', '');
}
