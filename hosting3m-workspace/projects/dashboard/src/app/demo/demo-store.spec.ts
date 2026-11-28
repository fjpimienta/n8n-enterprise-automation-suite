import { HttpRequest, HttpResponse } from '@angular/common/http';
import { TestBed } from '@angular/core/testing';
import { firstValueFrom } from 'rxjs';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { environment } from '@env/environment';
import { buildDemoRooms } from './demo-data';
import { demoMockInterceptor } from './demo-mock.interceptor';
import { applyRoomUpdate, resetDemoStore, withCleaningOverrides } from './demo-store';

const update = (id: unknown, fields: unknown, operation = 'update') => ({ operation, id, fields });
const cleaningOf = (id: number) => withCleaningOverrides(buildDemoRooms()).find(r => r.id === id)!.cleaning_status;

async function call(table: string, body: unknown, search = ''): Promise<any> {
  vi.stubGlobal('location', { search });
  const req = new HttpRequest('POST', `${environment.apiUrl_crud}/${table}`, body);
  const next = () => { throw new Error('mock must never forward the request'); };
  const res = await TestBed.runInInjectionContext(() => firstValueFrom(demoMockInterceptor(req, next as any))) as HttpResponse<any>;
  return res.body;
}

describe('demo store (in-memory, cleaning only)', () => {
  beforeEach(() => resetDemoStore());
  afterEach(() => { resetDemoStore(); vi.unstubAllGlobals(); });

  it('applies a valid cleaning update to the overlay and leaves the seed untouched', () => {
    expect(cleaningOf(3)).toBe('dirty');
    expect(applyRoomUpdate(update(3, { cleaning_status: 'clean' }))).toEqual({ ok: true, id: 3, fields: { cleaning_status: 'clean' } });
    expect(cleaningOf(3)).toBe('clean');
    expect(buildDemoRooms().find(r => r.id === 3)!.cleaning_status).toBe('dirty');
  });

  it('accepts a numeric id sent as text', () => {
    expect(applyRoomUpdate(update('3', { cleaning_status: 'clean' })).ok).toBe(true);
  });

  it.each([
    ['another field', update(3, { price_night: '1.00' })],
    ['a status other than available', update(3, { status: 'occupied' })],
    ['cleaning plus an unrelated field', update(3, { cleaning_status: 'clean', price_night: '1.00' })],
    ['a value outside the set', update(3, { cleaning_status: 'in_progress' })],
    ['a non-text value', update(3, { cleaning_status: 1 })],
    ['an unknown room', update(999, { cleaning_status: 'clean' })],
    ['id 0', update(0, { cleaning_status: 'clean' })],
    ['a fractional id', update(1.5, { cleaning_status: 'clean' })],
    ['a missing id', update(undefined, { cleaning_status: 'clean' })],
    ['an array as fields', update(3, ['cleaning_status'])],
    ['no fields', update(3, undefined)],
    ['another operation', update(3, { cleaning_status: 'clean' }, 'insert')],
    ['a null body', null]
  ])('refuses %s and changes nothing', (_name, body) => {
    expect(applyRoomUpdate(body).ok).toBe(false);
    expect(cleaningOf(3)).toBe('dirty');
  });

  it('is module memory only: it never touches browser storage', () => {
    const setItem = vi.spyOn(Storage.prototype, 'setItem');
    applyRoomUpdate(update(3, { cleaning_status: 'clean' }));
    expect(setItem).not.toHaveBeenCalled();
    setItem.mockRestore();
  });

  it('reset restores the seed', () => {
    applyRoomUpdate(update(3, { cleaning_status: 'clean' }));
    resetDemoStore();
    expect(cleaningOf(3)).toBe('dirty');
  });
});

describe('demoMockInterceptor: housekeeping write', () => {
  beforeEach(() => resetDemoStore());
  afterEach(() => { resetDemoStore(); vi.unstubAllGlobals(); });

  it('accepts the cleaning update and the next read shows it (no forward)', async () => {
    const ok = await call('hotel_rooms', update(3, { cleaning_status: 'clean' }));
    expect(ok.error).toBe(false);
    const read = await call('hotel_rooms', { operation: 'getall' });
    expect(read.data.find((r: any) => r.id === 3).cleaning_status).toBe('clean');
  });

  it('still refuses every other write', async () => {
    expect((await call('hotel_rooms', update(3, { status: 'occupied' }))).error).toBe(true);
    expect((await call('hotel_rooms', update(3, { price_night: '1.00' }))).error).toBe(true);
    expect((await call('hotel_rooms', { operation: 'insert', fields: { room_number: '999' } })).error).toBe(true);
    expect((await call('hotel_rooms', { operation: 'delete', id: 3 })).error).toBe(true);
    expect((await call('hotel_bookings', update(1, { status: 'cancelled' }))).error).toBe(true);
    expect((await call('hotel_room_inspections', { operation: 'insert', fields: {} })).error).toBe(true);
    expect((await call('hotel_maintenance_tickets', update(1, { status: 'RESOLVED' }))).error).toBe(true); // resolved_at is required
    expect((await call('hotel_maintenance_tickets', update(1, { status: 'PENDING', resolved_at: '2026-11-28T18:00:00.000Z' }))).error).toBe(true);
    expect((await call('hotel_maintenance_tickets', update(1, { status: 'RESOLVED', resolved_at: '2026-11-28T18:00:00.000Z', cost: '1' }))).error).toBe(true);
    expect((await call('hotel_maintenance_tickets', { operation: 'delete', id: 1 })).error).toBe(true);
    const read = await call('hotel_rooms', { operation: 'getall' });
    expect(read.data.find((r: any) => r.id === 3).cleaning_status).toBe('dirty');
  });

  it.each(['error', 'empty', 'writeerror'])('refuses the write in the "%s" scenario', async scenario => {
    const res = await call('hotel_rooms', update(3, { cleaning_status: 'clean' }), `?demo=${scenario}`);
    expect(res.error).toBe(true);
    const read = await call('hotel_rooms', { operation: 'getall' });
    expect(read.data.find((r: any) => r.id === 3).cleaning_status).toBe('dirty');
  });

  it('writeerror keeps reads normal', async () => {
    const read = await call('hotel_rooms', { operation: 'getall' }, '?demo=writeerror');
    expect(read.error).toBe(false);
    expect(read.data.length).toBe(18);
  });
});

describe('demo store: room status and ticket resolution', () => {
  const roomStatus = async (id: number) => (await call('hotel_rooms', { operation: 'getall' })).data.find((r: any) => r.id === id);
  const tickets = async (body: object = { operation: 'getall' }) => (await call('hotel_maintenance_tickets', body)).data as any[];
  const resolve = (id: unknown, fields: unknown = { status: 'RESOLVED', resolved_at: '2026-11-28T18:00:00.000Z' }) => update(id, fields);

  beforeEach(() => resetDemoStore());
  afterEach(() => { resetDemoStore(); vi.unstubAllGlobals(); });

  it('frees a room (available + dirty) in memory and leaves the seed untouched', async () => {
    expect((await call('hotel_rooms', update(5, { status: 'available', cleaning_status: 'dirty' }))).error).toBe(false);
    expect(await roomStatus(5)).toMatchObject({ status: 'available', cleaning_status: 'dirty' });
    expect(buildDemoRooms().find(r => r.id === 5)).toMatchObject({ status: 'maintenance', cleaning_status: 'clean' });
  });

  it('resolves a ticket in memory; the next read shows status and resolved_at; other tickets are untouched', async () => {
    expect((await call('hotel_maintenance_tickets', resolve(3))).error).toBe(false);
    const t = (await tickets()).find(x => x.id === 3);
    expect(t).toMatchObject({ status: 'RESOLVED', resolved_at: '2026-11-28T18:00:00.000Z' });
    expect((await tickets()).find(x => x.id === 1).status).toBe('PENDING');
  });

  it('filters tickets by room and by status when asked', async () => {
    const room5 = await tickets({ operation: 'getall', filters: { room_id: 5 } });
    expect(room5.length).toBeGreaterThan(0);
    expect(room5.every(t => t.room_id === 5)).toBe(true);
    const pending = await tickets({ operation: 'getall', filters: { status: 'PENDING' } });
    expect(pending.every(t => t.status === 'PENDING')).toBe(true);
  });

  it.each([
    ['an unknown ticket', resolve(999)],
    ['a ticket id of 0', resolve(0)],
    ['an unreadable resolved_at', resolve(3, { status: 'RESOLVED', resolved_at: 'not a date' })],
    ['a missing resolved_at', resolve(3, { status: 'RESOLVED' })],
    ['status only plus a solution text', resolve(3, { status: 'RESOLVED', resolved_at: '2026-11-28T18:00:00.000Z', solution_details: 'x' })],
    ['an array as fields', resolve(3, ['status'])]
  ])('refuses %s and changes nothing', async (_n, body) => {
    expect((await call('hotel_maintenance_tickets', body)).error).toBe(true);
    expect((await tickets()).filter(t => t.status === 'RESOLVED').length).toBe(1); // only the seed's resolved ticket
  });

  it.each(['error', 'empty', 'writeerror'])('refuses the ticket write in the "%s" scenario', async scenario => {
    expect((await call('hotel_maintenance_tickets', resolve(3), `?demo=${scenario}`)).error).toBe(true);
    expect((await tickets()).find(x => x.id === 3).status).toBe('PENDING');
  });

  it('sign-in: viewer gets a role with no action, editor EDITOR, anything else ADMIN', async () => {
    const role = async (user: string) => {
      vi.stubGlobal('location', { search: '' });
      const req = new HttpRequest('POST', environment.apiUrl_token, { user });
      const res = await TestBed.runInInjectionContext(() => firstValueFrom(demoMockInterceptor(req, (() => { throw new Error('no forward'); }) as any))) as HttpResponse<any>;
      return JSON.parse(atob(res.body.data.token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/'))).role;
    };
    expect([await role('viewer'), await role('editor'), await role('admin')]).toEqual(['CUSTOMER', 'EDITOR', 'ADMIN']);
  });
});
