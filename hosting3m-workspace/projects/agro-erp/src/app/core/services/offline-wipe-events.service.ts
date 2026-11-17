import { Injectable } from '@angular/core';
import { Observable, Subject } from 'rxjs';

/**
 * Notifies in-memory consumers (the herd, the unlock state) that the offline copy was wiped by the expiry
 * check. Dependency-free on purpose: consumers inject it without pulling in the store or the PIN database.
 */
@Injectable({ providedIn: 'root' })
export class OfflineWipeEventsService {
  private readonly wipedSubject = new Subject<void>();
  readonly wiped$: Observable<void> = this.wipedSubject.asObservable();

  /**
   * True while the offline copy is known to be wiped for an ENDED session (expired, unreadable or no token).
   * Set by the expiry check; cleared by a valid or in-grace check and by a login. While it is set, a logout
   * does not wipe again: nothing can be written to the copy in an ended session (T6).
   */
  private expiredWipeHeld = false;

  isExpiredWipeHeld(): boolean {
    return this.expiredWipeHeld;
  }

  setExpiredWipeHeld(held: boolean): void {
    this.expiredWipeHeld = held;
  }

  /** Emitted only when a wipe was due because the stored token ended (or is missing), once per stored value. */
  notifyWiped(): void {
    this.wipedSubject.next();
  }
}
