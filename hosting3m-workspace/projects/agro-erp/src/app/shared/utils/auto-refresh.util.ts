/** Pure timing check for the dashboard's auto-refresh cycle — kept free of Angular signals
 *  and `document` so it is trivially unit-testable (see auto-refresh.util.spec.ts).
 *
 *  `lastRefreshedAt === null` means "never refreshed yet" and is always due.
 */
export function isAutoRefreshDue(lastRefreshedAt: Date | null, nowMs: number, intervalMs: number): boolean {
  if (!lastRefreshedAt) return true;
  return nowMs - lastRefreshedAt.getTime() >= intervalMs;
}
