import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { describe, expect, it } from 'vitest';
import { environment } from '@env/environment';
import { AdminService } from '@features/admin/services/admin.service';
import { HttpHeaders } from '@angular/common/http';
import { TicketResolutionService } from './ticket-resolution.service';

function setup() {
  TestBed.configureTestingModule({
    providers: [provideHttpClient(), provideHttpClientTesting(), TicketResolutionService,
      { provide: AdminService, useValue: { getAuthHeaders: () => new HttpHeaders({ 'X-Test': '1' }) } }]
  });
  return { service: TestBed.inject(TicketResolutionService), http: TestBed.inject(HttpTestingController) };
}
const url = (t: string) => `${environment.apiUrl_crud}/${t}`;

describe('TicketResolutionService', () => {
  it('resolves with exactly status + resolved_at (ISO instant) at the root id, nothing else', async () => {
    const { service, http } = setup();
    const p = service.resolveTicket(7, new Date('2026-11-28T18:30:15.123Z'));
    const req = http.expectOne(url('hotel_maintenance_tickets'));
    expect(req.request.body).toEqual({
      operation: 'update', table_name: 'hotel_maintenance_tickets', id: 7, fields: { status: 'RESOLVED', resolved_at: '2026-11-28T18:30:15.123Z' }
    });
    req.flush({ error: false, data: [{ id: 7 }] });
    await p;
  });

  it('writes a room with only the given fields', async () => {
    const { service, http } = setup();
    const p = service.updateRoom(5, { status: 'available', cleaning_status: 'dirty' });
    const req = http.expectOne(url('hotel_rooms'));
    expect(req.request.body).toEqual({ operation: 'update', id: 5, fields: { status: 'available', cleaning_status: 'dirty' } });
    req.flush({ error: false, data: [] });
    await p;
  });

  it('reads one room\'s tickets with a room filter and returns the rows (data:[{}] passes through for the adapter)', async () => {
    const { service, http } = setup();
    const p = service.loadRoomTickets(5);
    const req = http.expectOne(url('hotel_maintenance_tickets'));
    expect(req.request.body.filters).toEqual({ room_id: 5 });
    req.flush({ error: false, data: [{}] });
    expect(await p).toEqual([{}]);
  });

  it('Silent Error Shield: HTTP 200 with error:true throws on every call', async () => {
    const { service, http } = setup();
    const calls = [service.loadRoomTickets(1), service.resolveTicket(1), service.updateRoom(1, { cleaning_status: 'dirty' })];
    http.match(() => true).forEach(r => r.flush({ error: true, message: 'Fallo DB', data: [] }));
    for (const c of calls) await expect(c).rejects.toThrow('Fallo DB');
  });

  it('sends the headers the app provides', async () => {
    const { service, http } = setup();
    const p = service.resolveTicket(1);
    const req = http.expectOne(url('hotel_maintenance_tickets'));
    expect(req.request.headers.get('X-Test')).toBe('1');
    req.flush({ error: false, data: [] });
    await p;
  });
});
