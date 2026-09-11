const TIMEZONE = 'America/Mexico_City';

/**
 * Medianoche (00:00 del día siguiente) en `America/Mexico_City` del día en que se creó
 * la solicitud, como instante UTC real.
 *
 * `fechaSolicitud` llega del gateway representando un instante UTC: el servidor Postgres
 * corre con `timezone = Etc/UTC` (confirmado) y `fecha_solicitud` usa `now()` como default,
 * aunque la columna sea `timestamp without time zone` — nunca se interpreta el valor crudo
 * como si ya fuera hora local de Chiapas/Tabasco.
 */
export function getAuthorizationDeadline(fechaSolicitud: string): Date {
  const hasTzSuffix = /[Zz]|[+-]\d{2}:?\d{2}$/.test(fechaSolicitud);
  const createdAtUtc = new Date(hasTzSuffix ? fechaSolicitud : `${fechaSolicitud}Z`);

  // Fecha calendario (YYYY-MM-DD) en hora local de Chiapas/Tabasco del momento de creación.
  const localDateStr = new Intl.DateTimeFormat('en-CA', {
    timeZone: TIMEZONE,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit'
  }).format(createdAtUtc);

  const nextDayGuess = new Date(`${localDateStr}T00:00:00Z`);
  nextDayGuess.setUTCDate(nextDayGuess.getUTCDate() + 1);

  return zonedMidnightToUtc(nextDayGuess, TIMEZONE);
}

/**
 * Dado un instante cuyo valor UTC literal coincide con el wall-clock objetivo (p.ej.
 * "2026-09-12T00:00:00" interpretado ingenuamente como UTC), devuelve el instante UTC real
 * en que ese mismo wall-clock ocurre en `timeZone`. Mide el offset dinámicamente (no asume
 * -06:00 fijo) para no romperse si la política de horario de verano cambia.
 */
function zonedMidnightToUtc(naiveUtcGuess: Date, timeZone: string): Date {
  const asIfUtc = new Date(naiveUtcGuess.toLocaleString('en-US', { timeZone: 'UTC' }));
  const asIfZoned = new Date(naiveUtcGuess.toLocaleString('en-US', { timeZone }));
  const offsetMs = asIfUtc.getTime() - asIfZoned.getTime();
  return new Date(naiveUtcGuess.getTime() + offsetMs);
}

export type CountdownSeverity = 'ok' | 'warning' | 'danger';

/** Verde (>4h), amarillo (≤4h), rojo (<1h) — umbrales tal cual definidos en el alcance. */
export function getCountdownSeverity(msRemaining: number): CountdownSeverity {
  if (msRemaining < 60 * 60 * 1000) return 'danger';
  if (msRemaining <= 4 * 60 * 60 * 1000) return 'warning';
  return 'ok';
}

export function formatCountdown(msRemaining: number): string {
  if (msRemaining <= 0) return 'Vencida';
  const totalMinutes = Math.floor(msRemaining / 60000);
  const hours = Math.floor(totalMinutes / 60);
  const minutes = totalMinutes % 60;
  return `${hours}h ${minutes}m`;
}
