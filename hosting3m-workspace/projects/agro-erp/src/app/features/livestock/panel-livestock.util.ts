/** Time zone of every date the panel registration treats as "today" (matches fn_livestock_chat_today). */
export const PANEL_TIME_ZONE = 'America/Mexico_City';

/**
 * Today's calendar date (YYYY-MM-DD) in America/Mexico_City.
 * `toISOString().split('T')[0]` is the UTC date, which is already "tomorrow" in CDMX from 18:00.
 */
export function todayInMexicoCity(now: Date = new Date()): string {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: PANEL_TIME_ZONE,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit'
  }).formatToParts(now);
  const get = (type: string) => parts.find(p => p.type === type)?.value ?? '';
  return `${get('year')}-${get('month')}-${get('day')}`;
}

/** Roles that may use the NEW panel ALTA flow. OWNER is deliberately excluded (no DB permission change). */
const PANEL_ALTA_ROLES: readonly string[] = ['ADMIN', 'EDITOR'];

export function canUsePanelAlta(role: string | null | undefined): boolean {
  return PANEL_ALTA_ROLES.includes((role ?? '').trim().toUpperCase());
}
