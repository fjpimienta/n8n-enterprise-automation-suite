/** localStorage key of the "wipe not confirmed" flag. A boolean only: no data, no token, no scope. */
export const WIPE_PENDING_KEY = 'agroerp-offline-wipe-pending';

/**
 * True when a wipe of the offline cache could not be confirmed (#1087, phase 1b-iii-c). While it is set the
 * cache is not served and not written. Unreadable storage counts as pending (fail-closed).
 */
export function isWipePending(): boolean {
  try {
    return localStorage.getItem(WIPE_PENDING_KEY) === '1';
  } catch {
    return true;
  }
}

/** Sets or clears the flag. A storage failure is ignored: `isWipePending()` already fails closed then. */
export function setWipePending(pending: boolean): void {
  try {
    if (pending) localStorage.setItem(WIPE_PENDING_KEY, '1');
    else localStorage.removeItem(WIPE_PENDING_KEY);
  } catch {
    // Storage unavailable: the read side fails closed.
  }
}
