import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpErrorResponse } from '@angular/common/http';
import { Observable, catchError, delay, map, of, throwError, timeout } from 'rxjs';
import { RUNTIME } from './runtime-config';

/** Server-side limits of POST /v6/contact. The client mirrors them; the server stays authoritative. */
export const CONTACT_LIMITS = {
  names: 100,
  middlename: 100,
  lastname: 100,
  phone: 30,
  email: 150,
  message: 2000,
  service: 60,
} as const;

/** Services offered in the form (each value must stay within CONTACT_LIMITS.service). */
export const CONTACT_SERVICES: readonly string[] = [
  'Renta de Servidores VPS',
  'Automatización de Procesos con Agentes IA',
  'Registro de Dominios',
  'Creación de Páginas Web',
  'Sistemas de Cómputo en la Nube',
  'Correo electrónico',
];

export interface ContactFormValue {
  names: string;
  middlename: string;
  lastname: string;
  phone: string;
  email: string;
  message: string;
  service: string;
  /** Honeypot: hidden field that must stay empty. */
  empresa: string;
}

export type ContactErrorKind = 'validation' | 'turnstile' | 'network';

export class ContactError extends Error {
  constructor(readonly kind: ContactErrorKind) {
    super(kind);
  }
}

/** Body of POST /v6/contact. Note: no tenant id is ever sent; the server fixes the tenant. */
export function buildContactPayload(value: ContactFormValue, turnstileToken: string): Record<string, string> {
  const clean = (text: string, max: number) => text.trim().slice(0, max);
  return {
    names: clean(value.names, CONTACT_LIMITS.names),
    middlename: clean(value.middlename, CONTACT_LIMITS.middlename),
    lastname: clean(value.lastname, CONTACT_LIMITS.lastname),
    phone: clean(value.phone, CONTACT_LIMITS.phone),
    email: clean(value.email, CONTACT_LIMITS.email),
    message: clean(value.message, CONTACT_LIMITS.message),
    service: CONTACT_SERVICES.includes(value.service) ? value.service : '',
    'cf-turnstile-response': turnstileToken,
    empresa: '',
  };
}

/** Maps an HTTP failure to a user-facing error kind. */
export function toContactError(err: unknown): ContactError {
  if (err instanceof ContactError) return err;
  if (err instanceof HttpErrorResponse) {
    if (err.status === 400) return new ContactError('validation');
    if (err.status === 401) return new ContactError('turnstile');
  }
  return new ContactError('network');
}

@Injectable({ providedIn: 'root' })
export class ContactService {
  private readonly http = inject(HttpClient);

  send(value: ContactFormValue, turnstileToken: string): Observable<void> {
    if (RUNTIME.mockApi) return of(undefined).pipe(delay(600));

    return this.http
      .post<{ success?: boolean }>(`${RUNTIME.apiBase}/v6/contact`, buildContactPayload(value, turnstileToken))
      .pipe(
        timeout(15000),
        // A failed n8n execution can answer HTTP 200 with an empty body: only an explicit success counts.
        map((res) => {
          if (res?.success !== true) throw new ContactError('network');
        }),
        catchError((e) => throwError(() => toContactError(e))),
      );
  }
}

