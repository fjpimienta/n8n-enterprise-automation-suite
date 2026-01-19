import { HttpClient } from '@angular/common/http';
import { inject, Injectable, signal } from '@angular/core';
import { environment } from '@env/environment';
import { AdminService } from '@features/admin/services/admin.service';
import { lastValueFrom } from 'rxjs/internal/lastValueFrom';

@Injectable({
  providedIn: 'root',
})
export class ReportService {
  private http = inject(HttpClient);
  private apiUrl_crud = environment.apiUrl_crud;
  public loadingReports = signal<boolean>(false);
  public adminService = inject(AdminService);

  /** Calcula el reporte diario, semanal, mensual o anual */
  calculateDailyReport(bookings: any[], filter: 'day' | 'week' | 'month' | 'year') {
    const now = new Date();
    const todayStr = this.getLocalDateString(now);

    const filtered = bookings.filter((b: any) => {
      if (!b.created_at) return false;
      const createdDate = new Date(b.created_at);
      const createdStr = this.getLocalDateString(createdDate);

      switch (filter) {
        case 'day': return createdStr === todayStr;
        case 'week':
          const weekAgo = new Date();
          weekAgo.setDate(now.getDate() - 7);
          return createdDate >= weekAgo;
        case 'month':
          return createdDate.getMonth() === now.getMonth() && createdDate.getFullYear() === now.getFullYear();
        case 'year':
          return createdDate.getFullYear() === now.getFullYear();
        default: return createdStr === todayStr;
      }
    });

    const stats = { total: 0, paid: 0, pending: 0, transactions: filtered };

    filtered.forEach(b => {
      const amount = parseFloat(b.total_amount || 0);
      stats.total += amount;
      if (b.payment_status === 'paid') stats.paid += amount;
      else stats.pending += amount;
    });

    return stats;
  }

  /* Convierte una fecha a string local YYYY-MM-DD */
  private getLocalDateString(date: Date): string {
    const offset = date.getTimezoneOffset();
    const localDate = new Date(date.getTime() - (offset * 60 * 1000));
    return localDate.toISOString().split('T')[0];
  }

  /* Obtiene todas las reservas en bruto para generar reportes */
  async getRawBookingsForReport(): Promise<any[]> {
    this.loadingReports.set(true);
    try {
      const res: any = await lastValueFrom(
        this.http.post(`${this.apiUrl_crud}/hotel_bookings`, {
          operation: 'getall',
          fields: { id_company: 1 }
        }, { headers: this.adminService.getAuthHeaders() })
      );
      return Array.isArray(res?.data) ? res.data : [];
    } finally {
      this.loadingReports.set(false);
    }
  }
}
