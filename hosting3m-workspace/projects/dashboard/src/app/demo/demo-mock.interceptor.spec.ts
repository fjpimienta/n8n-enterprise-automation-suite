import { HttpRequest, HttpResponse } from '@angular/common/http';
import { firstValueFrom } from 'rxjs';
import { TestBed } from '@angular/core/testing';
import { describe, expect, it } from 'vitest';
import { environment } from '@env/environment';
import { buildDemoBookings, buildDemoRooms, dayOffsetStamp } from './demo-data';
import { buildDemoToken, demoMockInterceptor, scenarioFromSearch } from './demo-mock.interceptor';

async function call(url: string, body: unknown): Promise<any> {
  const req = new HttpRequest('POST', url, body);
  const next = () => { throw new Error('mock must never forward the request'); };
  const res = await TestBed.runInInjectionContext(() =>
    firstValueFrom(demoMockInterceptor(req, next as any))) as HttpResponse<any>;
  expect(res.status).toBe(200);
  return res.body;
}

describe('demo data', () => {
  it('has 18 rooms: 5 Sencilla, 4 King, 8 Doble, 1 Triple, with string numerics', () => {
    const rooms = buildDemoRooms();
    const count = (t: string) => rooms.filter(r => r.type === t).length;
    expect(rooms.length).toBe(18);
    expect([count('SENCILLA'), count('KING'), count('DOBLE'), count('TRIPLE')]).toEqual([5, 4, 8, 1]);
    expect(rooms.every(r => typeof r.price_night === 'string' && typeof r.room_number === 'string')).toBe(true);
  });

  it('stamps dates as midnight UTC on the local calendar day (no toISOString day shift)', () => {
    const base = new Date(2026, 10, 27, 23, 30); // 23:30 local
    expect(dayOffsetStamp(0, base)).toBe('2026-11-27T00:00:00.000Z');
    expect(dayOffsetStamp(1, base)).toBe('2026-11-28T00:00:00.000Z');
  });

  it('uses initials only for guests', () => {
    expect(buildDemoBookings().every(b => /^[A-Z]\. [A-Z]\.$/.test(b.hotel_guests_data.full_name))).toBe(true);
  });
});

describe('demoMockInterceptor', () => {
  it('answers getall for rooms and never forwards', async () => {
    const res = await call(`${environment.apiUrl_crud}/hotel_rooms`, { operation: 'getall' });
    expect(res.error).toBe(false);
    expect(res.data.length).toBe(18);
  });

  it('filters tickets by status', async () => {
    const res = await call(`${environment.apiUrl_crud}/hotel_maintenance_tickets`, { operation: 'getall', fields: { status: 'PENDING' } });
    expect(res.data.every((t: any) => t.status === 'PENDING')).toBe(true);
  });

  it('refuses writes with error:true on HTTP 200', async () => {
    const res = await call(`${environment.apiUrl_crud}/hotel_bookings`, { operation: 'insert' });
    expect(res.error).toBe(true);
  });

  it('returns an error body for unknown endpoints instead of forwarding', async () => {
    const res = await call('https://other.invalid/x', {});
    expect(res.error).toBe(true);
  });

  it('login: select_company for "multi", token otherwise, EDITOR role for "editor"', async () => {
    const step1 = await call(environment.apiUrl_token, { user: 'multi', pass: 'x' });
    expect(step1.status).toBe('select_company');
    const editor = await call(environment.apiUrl_token, { user: 'editor', pass: 'x' });
    expect(JSON.parse(atob(editor.data.token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/'))).role).toBe('EDITOR');
  });

  it('builds a token whose exp is in the future', () => {
    const payload = JSON.parse(atob(buildDemoToken('ADMIN').split('.')[1].replace(/-/g, '+').replace(/_/g, '/')));
    expect(payload.exp).toBeGreaterThan(Date.now() / 1000);
    expect(payload.email.endsWith('.invalid')).toBe(true);
  });

  it('parses scenarios', () => {
    expect(scenarioFromSearch('?demo=empty')).toBe('empty');
    expect(scenarioFromSearch('?demo=error')).toBe('error');
    expect(scenarioFromSearch('?demo=zzz')).toBe('normal');
  });
});
