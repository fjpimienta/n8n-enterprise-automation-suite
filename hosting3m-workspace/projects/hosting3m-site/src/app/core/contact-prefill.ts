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

  apply(service: string, message: string): void {
    this.request.set({ service: service.trim().slice(0, 60), message, seq: (this.request()?.seq ?? 0) + 1 });
  }
}
