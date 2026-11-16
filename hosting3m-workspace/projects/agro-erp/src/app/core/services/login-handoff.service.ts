import { Injectable } from '@angular/core';

/**
 * Remembers who was signed in when a login request left the device (#1087, phase 1b-iii-b). The login
 * replaces the stored token, so the previous identity must be captured BEFORE the request is sent.
 *
 * Memory only, one slot: each login POST overwrites it, so a failed attempt never leaves a stale value.
 * If the page reloads between the POST and the response, the slot is empty, and the login is then
 * treated as "previous user unknown" (fail-closed: the offline copy is wiped).
 */
@Injectable({ providedIn: 'root' })
export class LoginHandoffService {
  private pending: { previousUser: string | null } | null = null;

  begin(previousUser: string | null): void {
    this.pending = { previousUser };
  }

  /** Returns and clears the captured identity. `null` when no login request was observed. */
  consume(): { previousUser: string | null } | null {
    const captured = this.pending;
    this.pending = null;
    return captured;
  }
}
