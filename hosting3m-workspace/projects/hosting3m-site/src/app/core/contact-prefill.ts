import { Injectable, signal } from '@angular/core';

export interface PrefillRequest {
  /** Service label to select (a catalog `service_label`, max 60 characters); empty means "leave as is". */
  readonly service: string;
  /** Text for the message field; applied only when the field is empty. */
  readonly message: string;
  /** Changes on every call so the form reacts even to an identical request. */
  readonly seq: number;
}

/** One-way channel from the plans section to the contact form. Carries no personal data and is never sent as is. */
@Injectable({ providedIn: 'root' })
export class ContactPrefill {
  readonly request = signal<PrefillRequest | null>(null);
  /** Last text this service wrote into the message field; only that text may be replaced later. */
  private lastWritten = '';

  /**
   * Returns the text to put in the message field, or null to leave it alone.
   * Replaces an empty field or our own previous text; never text the visitor wrote or edited.
   */
  messageFor(current: string, wanted: string): string | null {
    if (!wanted) return null;
    if (current.trim() !== '' && current !== this.lastWritten) return null;
    this.lastWritten = wanted;
    return wanted;
  }

  apply(service: string, message: string): void {
    this.request.set({ service: service.trim().slice(0, 60), message, seq: (this.request()?.seq ?? 0) + 1 });
  }
}
