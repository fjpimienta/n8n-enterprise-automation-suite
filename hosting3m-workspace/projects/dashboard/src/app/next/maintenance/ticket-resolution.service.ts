import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { environment } from '@env/environment';
import { AdminService } from '@features/admin/services/admin.service';
import { lastValueFrom } from 'rxjs';
import { RoomWrite, buildResolveFields } from '../logic/resolution';

/**
 * The only writes of the `next` maintenance board. Three calls, each one a single gateway request:
 *  - `loadRoomTickets`: fresh read of the tickets of one room (decides whether other faults remain);
 *  - `resolveTicket`: update with exactly `status: 'RESOLVED'` and `resolved_at` (same format as the classic flow);
 *  - `updateRoom`: update of `status` / `cleaning_status` only.
 * Every call applies the Silent Error Shield (HTTP 200 with `error: true` is thrown). The classic
 * `MaintenanceService` is not used for writes because it hides `error:true`.
 */
@Injectable({ providedIn: 'root' })
export class TicketResolutionService {
  private readonly http = inject(HttpClient);
  private readonly admin = inject(AdminService);
  private readonly base = environment.apiUrl_crud;

  private async post(table: string, body: object): Promise<any> {
    const res: any = await lastValueFrom(this.http.post(`${this.base}/${table}`, body, { headers: this.admin.getAuthHeaders() }));
    // 🛑 Silent Error Shield: Postgres errors arrive as HTTP 200 with error:true.
    if (res?.error) throw new Error(res.message || 'Gateway error');
    return res;
  }

  /** Rows as the gateway sends them (loosely typed; adapt with `toTicketViews`). Throws on error. */
  async loadRoomTickets(roomId: number): Promise<unknown[]> {
    const res = await this.post('hotel_maintenance_tickets', {
      operation: 'getall', table_name: 'hotel_maintenance_tickets', action: 'list', filters: { room_id: roomId }
    });
    return Array.isArray(res?.data) ? res.data : [];
  }

  async resolveTicket(ticketId: number, now: Date = new Date()): Promise<void> {
    await this.post('hotel_maintenance_tickets', {
      operation: 'update', table_name: 'hotel_maintenance_tickets', id: ticketId, fields: buildResolveFields(now)
    });
  }

  async updateRoom(roomId: number, fields: RoomWrite): Promise<void> {
    await this.post('hotel_rooms', { operation: 'update', id: roomId, fields });
  }
}
