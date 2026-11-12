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

export const PANEL_WEIGHT_ERROR = 'El peso debe ser un número (por ejemplo 412.5).';
export const PANEL_WEIGHT_POSITIVE_ERROR = 'El peso debe ser un número de kilos mayor que 0 (o déjalo vacío).';

/**
 * Local weight check before calling the service: "412,5" is fine, empty is fine, non-numeric is not, and
 * neither is zero ("0", "0,0", "0.00"). The service keeps its own numeric check.
 */
export function validatePanelWeight(value: unknown): string | null {
  if (value === null || value === undefined) return null;
  const raw = String(value).replace(/\s+/g, '').replace(',', '.');
  if (raw === '') return null;
  if (!/^\d+(\.\d+)?$/.test(raw)) return PANEL_WEIGHT_ERROR;
  return Number(raw) > 0 ? null : PANEL_WEIGHT_POSITIVE_ERROR;
}

/** Fixed, human order of the preview / existing-animal rows. Unknown keys go last, as received. */
export const PANEL_ROW_ORDER: readonly string[] = [
  'empresa', 'upp', 'upp_code', 'lote', 'especie', 'categoria', 'modelo_negocio', 'arete', 'sin_arete_oficial',
  'numero_fuego', 'rfid_electronico', 'peso_kg', 'fecha_nacimiento', 'upp_origen', 'prueba_tb', 'prueba_br', 'notas'
];

export function orderPanelEntries(values: Record<string, unknown> | null | undefined): [string, unknown][] {
  const entries = Object.entries(values ?? {});
  const rank = (key: string) => PANEL_ROW_ORDER.indexOf(key);
  const known = entries.filter(([k]) => rank(k) >= 0).sort((a, b) => rank(a[0]) - rank(b[0]));
  const unknown = entries.filter(([k]) => rank(k) < 0);
  return [...known, ...unknown];
}
