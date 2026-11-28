import { HttpRequest, HttpResponse } from '@angular/common/http';
import { firstValueFrom } from 'rxjs';
import { TestBed } from '@angular/core/testing';
import { describe, expect, it } from 'vitest';
import { environment } from '@env/environment';
import { buildDemoBookings, buildDemoRooms, buildDemoTickets, dayOffsetStamp, ticketStamp } from './demo-data';
import { MT_OLD_AFTER_DAYS, reviewReasons, ticketAgeDays, toTicketViews } from '../next/logic/maintenance';
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

  it('synthetic tickets: open ones sit on rooms 5 and 9 only, so the tickets radar flags the same rooms as before', () => {
    const open = buildDemoTickets().filter(t => t.status === 'PENDING');
    expect([...new Set(open.map(t => t.room_id))].sort()).toEqual([5, 9]);
    expect(buildDemoTickets().some(t => t.status === 'RESOLVED')).toBe(true);
  });

  it('synthetic tickets cover ages around the threshold and the unhappy cases', () => {
    const now = new Date();
    const views = toTicketViews(buildDemoTickets(now));
    const ages = views.map(v => ticketAgeDays(v.createdAt, now));
    expect(ages).toContain(MT_OLD_AFTER_DAYS);
    expect(ages).toContain(MT_OLD_AFTER_DAYS + 1);
    expect(ages).toContain(0);
    const reasons = views.flatMap(v => reviewReasons(v));
    expect(reasons).toEqual(expect.arrayContaining(['no-id', 'no-content', 'unknown-priority']));
    expect(buildDemoTickets().some(t => t.id === undefined)).toBe(true);
    expect(buildDemoTickets().every(t => t.id_company === 9001)).toBe(true);
  });

  it('ticket stamps are noon in Mexico City (a whole-day offset in that calendar), never shifted by UTC', () => {
    expect(ticketStamp(0, new Date('2026-11-28T05:59:00.000Z'))).toBe('2026-11-27T18:00:00.000Z'); // 23:59 CDMX on the 27th
    expect(ticketStamp(0, new Date('2026-11-28T06:00:00.000Z'))).toBe('2026-11-28T18:00:00.000Z');
    expect(ticketStamp(3, new Date('2026-11-28T18:00:00.000Z'))).toBe('2026-11-25T18:00:00.000Z');
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
    expect(scenarioFromSearch('?demo=writeerror')).toBe('writeerror');
    expect(scenarioFromSearch('?demo=zzz')).toBe('normal');
  });
});
