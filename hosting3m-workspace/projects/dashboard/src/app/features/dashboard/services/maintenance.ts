import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
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

  // Obtener tickets (opcionalmente filtrados por estado o habitación)
  async getTickets(filters: any = {}) {
    const payload = {
      operation: 'getall',
      table_name: 'hotel_maintenance_tickets',
      filter: filters
    };
    return this.request(payload);
  }

  // Crear nuevo ticket
  async createTicket(ticket: any) {
    const payload = {
      operation: 'insert',
      table_name: 'hotel_maintenance_tickets',
      fields: {
        ...ticket,
        status: 'PENDING',
        created_at: new Date().toISOString()
      }
    };
    return this.request(payload);
  }

  // Actualizar estado (ej. de PENDING a RESOLVED)
  async updateTicket(id: number, data: any) {
    const payload = {
      operation: 'update',
      table_name: 'hotel_maintenance_tickets',
      id: id,
      fields: data
    };
    return this.request(payload);
  }

  // Helper privado para peticiones
  private async request(body: any) {
    try {
      const res: any = await lastValueFrom(
        this.http.post(`${this.apiUrl}/hotel_maintenance_tickets`, body, {
          headers: this.adminService.getAuthHeaders()
        })
      );
      return res.data || [];
    } catch (error) {
      console.error('Maintenance API Error:', error);
      throw error;
    }
  }
}