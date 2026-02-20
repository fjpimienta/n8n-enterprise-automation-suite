import { HttpClient } from '@angular/common/http';
import { Injectable, inject, signal } from '@angular/core';
import { environment } from '@env/environment';
import { AdminService } from '@features/admin/services/admin.service';
import { lastValueFrom } from 'rxjs';

@Injectable({
  providedIn: 'root'
})
export class MaintenanceService {
  private http = inject(HttpClient);
  private apiUrl = environment.apiUrl_crud;
  private adminService = inject(AdminService);

  /** Estado centralizado; evita peticiones duplicadas cuando varios componentes piden tickets */
  private readonly _tickets = signal<any[]>([]);
  readonly tickets = this._tickets.asReadonly();

  private _loadingTickets = signal(false);
  readonly loadingTickets = this._loadingTickets.asReadonly();

  private _lastFetchTime = 0;
  private static readonly CACHE_TTL_MS = 30_000; // 30 segundos

  /** Carga tickets con caché TTL; múltiples componentes comparten el mismo estado */
  async loadTickets(forceRefresh = false): Promise<any[]> {
    const now = Date.now();
    if (!forceRefresh && this._tickets().length > 0 && (now - this._lastFetchTime) < MaintenanceService.CACHE_TTL_MS) {
      return this._tickets();
    }

    this._loadingTickets.set(true);
    try {
      const data = await this.getTickets();
      const priorityVal: Record<string, number> = { 'CRITICAL': 3, 'NORMAL': 2, 'LOW': 1 };
      const sorted = [...data].sort((a: any, b: any) =>
        (priorityVal[b.priority] || 0) - (priorityVal[a.priority] || 0)
      );
      this._tickets.set(sorted);
      this._lastFetchTime = now;
      return sorted;
    } finally {
      this._loadingTickets.set(false);
    }
  }

  /** Invalida caché tras mutación (crear/actualizar ticket) */
  invalidateTicketsCache(): void {
    this._lastFetchTime = 0;
  }

  async getTickets(filters: any = {}): Promise<any[]> {
    const payload = {
      operation: 'getall',
      table_name: 'hotel_maintenance_tickets',
      action: 'list',
      filters: filters
    };
    const result = await this.request(payload);
    return Array.isArray(result) ? result : [];
  }

  async createTicket(ticket: any): Promise<any> {
    const payload = {
      operation: 'insert',
      table_name: 'hotel_maintenance_tickets',
      fields: {
        ...ticket,
        status: 'PENDING',
        created_at: new Date().toISOString()
      }
    };
    const res = await this.request(payload);
    this.invalidateTicketsCache();
    return res;
  }

  async updateTicket(id: number, data: any): Promise<any> {
    const payload = {
      operation: 'update',
      table_name: 'hotel_maintenance_tickets',
      id: id,
      fields: data
    };
    const res = await this.request(payload);
    this.invalidateTicketsCache();
    return res;
  }

  private async request(body: any): Promise<any> {
    try {
      const res: any = await lastValueFrom(
        this.http.post(`${this.apiUrl}/hotel_maintenance_tickets`, body, {
          headers: this.adminService.getAuthHeaders()
        })
      );
      return res.data ?? [];
    } catch (error) {
      console.error('Maintenance API Error:', error);
      throw error;
    }
  }
}
