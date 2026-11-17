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

  notifyWiped(): void {
    this.wipedSubject.next();
  }
}
