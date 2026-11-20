import { HttpErrorResponse } from '@angular/common/http';
import { CONTACT_LIMITS, CONTACT_SERVICES, ContactError, buildContactPayload, toContactError } from './contact';

const base = { names: ' Ana ', middlename: '', lastname: 'López', phone: '+52 999 390 2625', email: 'ana@example.com', message: 'Hola', service: CONTACT_SERVICES[0], empresa: '' };

describe('buildContactPayload', () => {
  it('matches the server contract and never carries a tenant id', () => {
    const p = buildContactPayload(base, 'tok');
    expect(Object.keys(p).sort()).toEqual(['cf-turnstile-response', 'email', 'empresa', 'lastname', 'message', 'middlename', 'names', 'phone', 'service']);
    expect(p['cf-turnstile-response']).toBe('tok');
    expect(p['names']).toBe('Ana');
  });

  it('forces the honeypot empty, truncates to server limits and drops unknown services', () => {
    const p = buildContactPayload({ ...base, empresa: 'bot', message: 'x'.repeat(5000), service: 'hack' }, 't');
    expect(p['empresa']).toBe('');
    expect(p['message']).toHaveLength(CONTACT_LIMITS.message);
    expect(p['service']).toBe('');
  });

  it('keeps every offered service within the 60 character limit', () => {
    for (const s of CONTACT_SERVICES) expect(s.length).toBeLessThanOrEqual(CONTACT_LIMITS.service);
  });
});

describe('toContactError', () => {
  it('maps 400 and 401 and defaults to network', () => {
    expect(toContactError(new HttpErrorResponse({ status: 400 })).kind).toBe('validation');
    expect(toContactError(new HttpErrorResponse({ status: 401 })).kind).toBe('turnstile');
    expect(toContactError(new HttpErrorResponse({ status: 500 })).kind).toBe('network');
    expect(toContactError(new Error('timeout')).kind).toBe('network');
    expect(toContactError(new ContactError('validation')).kind).toBe('validation');
  });
});
