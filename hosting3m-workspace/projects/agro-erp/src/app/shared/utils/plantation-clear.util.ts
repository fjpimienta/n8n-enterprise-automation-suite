import type { SessionState } from 'core-auth';

/**
 * Stored plantation choices are cleared when there is no session at all. A grace session is still a
 * session (its JWT is expired, but the cache and PIN flow rely on it), so a cold start in grace keeps them.
 */
export function shouldClearStoredPlantations(isAuthenticated: boolean, state: SessionState): boolean {
  return !isAuthenticated && state !== 'grace';
}
