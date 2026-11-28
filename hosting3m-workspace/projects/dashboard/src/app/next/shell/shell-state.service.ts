import { Injectable, signal } from '@angular/core';

/** UI-only state shared between the `next` shell and the home page. Holds no business data. */
@Injectable({ providedIn: 'root' })
export class ShellStateService {
  /** Set by the shell's expense buttons; the home page opens its expense modal and clears it. */
  readonly expensePending = signal(false);
  requestExpense(): void { this.expensePending.set(true); }
}
