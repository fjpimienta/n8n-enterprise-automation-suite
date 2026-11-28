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
    expect(applyRoomUpdate(update(3, { cleaning_status: 'clean' }))).toEqual({ ok: true, id: 3, cleaning_status: 'clean' });
    expect(cleaningOf(3)).toBe('clean');
    expect(buildDemoRooms().find(r => r.id === 3)!.cleaning_status).toBe('dirty');
  });

  it('accepts a numeric id sent as text', () => {
    expect(applyRoomUpdate(update('3', { cleaning_status: 'clean' })).ok).toBe(true);
  });

  it.each([
    ['another field', update(3, { status: 'available' })],
    ['cleaning plus another field', update(3, { cleaning_status: 'clean', status: 'available' })],
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
    expect((await call('hotel_rooms', update(3, { status: 'available', cleaning_status: 'clean' }))).error).toBe(true);
    expect((await call('hotel_rooms', { operation: 'insert', fields: { room_number: '999' } })).error).toBe(true);
    expect((await call('hotel_rooms', { operation: 'delete', id: 3 })).error).toBe(true);
    expect((await call('hotel_bookings', update(1, { status: 'cancelled' }))).error).toBe(true);
    expect((await call('hotel_room_inspections', { operation: 'insert', fields: {} })).error).toBe(true);
    expect((await call('hotel_maintenance_tickets', update(1, { status: 'RESOLVED' }))).error).toBe(true);
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
