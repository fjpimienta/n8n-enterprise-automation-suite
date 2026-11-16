/**
 * Single source of truth for "offline grace is configured" (#1087, phase 1b-iii-b). Same rule as core-auth's
 * `AuthService.getSessionState()`: `offlineGraceMs` must be a positive finite number. Without it the grace
 * state never exists, so the PIN setup, unlock flow, PIN records and the 60 s watch stay dormant.
 *
 * Fail-closed: any error while reading the configuration means "not enabled".
 */
export function isOfflineGraceEnabled(config: { offlineGraceMs?: unknown } | null | undefined): boolean {
  try {
    const ms = config?.offlineGraceMs;
    return typeof ms === 'number' && Number.isFinite(ms) && ms > 0;
  } catch {
    return false;
  }
}
