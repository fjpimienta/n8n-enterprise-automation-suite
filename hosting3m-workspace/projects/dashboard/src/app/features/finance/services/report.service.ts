import { HttpClient } from '@angular/common/http';
import { inject, Injectable, signal } from '@angular/core';
import { environment } from '@env/environment';
import { AdminService } from '@features/admin/services/admin.service';
import { lastValueFrom } from 'rxjs';

@Injectable({
  providedIn: 'root',
})
export class ReportService {
  private http = inject(HttpClient);
  private apiUrl_crud = environment.apiUrl_crud;
  public loadingReports = signal<boolean>(false);
  public adminService = inject(AdminService);

  /** * Calcula el reporte unificado (Ventas - Gastos = Balance) 
   * Acepta 'bookings' Y 'expenses'
   */
  calculateDailyReport(bookings: any[], expenses: any[], filter: 'day' | 'week' | 'month' | 'year') {
    const now = new Date();
    const todayStr = this.getLocalDateString(now);

    // 1. Filtramos las VENTAS según el rango seleccionado
    const filteredBookings = bookings.filter((b: any) =>
      this.isDateInPeriod(b.created_at, filter, now, todayStr)
    );

    // 2. Filtramos los GASTOS según el rango seleccionado
    const filteredExpenses = expenses.filter((e: any) =>
      e.status === 'APPROVED' && this.isDateInPeriod(e.expense_date, filter, now, todayStr)
    );

    // 3. Estructura de datos COMPLETA (Ventas + Gastos)
    const stats = {
      total_sales: 0,
      paid_in: 0,
      pending: 0,
      total_expenses: 0,
      balance: 0,
      transactions: filteredBookings,
      expenseTransactions: filteredExpenses,
      periodLabel: this.getPeriodLabel(filter)
    };

    // Sumar Ventas
    filteredBookings.forEach(b => {
      const amount = parseFloat(b.total_amount || 0);
      stats.total_sales += amount;
      if (b.payment_status === 'paid') stats.paid_in += amount;
      else stats.pending += amount;
    });

    // Sumar Gastos
    filteredExpenses.forEach(e => {
      stats.total_expenses += parseFloat(e.amount || 0);
    });

    // Calcular Balance (Lo que realmente queda en caja)
    stats.balance = stats.paid_in - stats.total_expenses;

    return stats;
  }

  /* Lógica centralizada de fechas (Aquí está la magia de los filtros) */
  private isDateInPeriod(dateStr: string, filter: string, now: Date, todayStr: string): boolean {
    if (!dateStr) return false;
    // Truco: Agregar 'T00:00:00' si viene solo fecha para evitar lios de zona horaria
    const dateObj = new Date(dateStr.includes('T') ? dateStr : dateStr + 'T12:00:00');
    const dateLocalStr = this.getLocalDateString(dateObj);

    switch (filter) {
      case 'day': return dateLocalStr === todayStr;

      case 'week':
        const startOfWeek = new Date(now);
        startOfWeek.setDate(now.getDate() - now.getDay()); // Ir al Domingo
        startOfWeek.setHours(0, 0, 0, 0);
        return dateObj >= startOfWeek;

      case 'month':
        return dateObj.getMonth() === now.getMonth() && dateObj.getFullYear() === now.getFullYear();

      case 'year':
        return dateObj.getFullYear() === now.getFullYear();

      default: return dateLocalStr === todayStr;
    }
  }

  private getLocalDateString(date: Date): string {
    const offset = date.getTimezoneOffset();
    const localDate = new Date(date.getTime() - (offset * 60 * 1000));
    return localDate.toISOString().split('T')[0];
  }

  private getPeriodLabel(filter: string): string {
    const labels: any = { 'day': 'Hoy', 'week': 'Esta Semana', 'month': 'Este Mes', 'year': 'Este Año' };
    return labels[filter] || 'Periodo';
  }

  /* Obtiene Ventas */
  async getRawBookingsForReport(): Promise<any[]> {
    return this.fetchData('hotel_bookings');
  }

  /* Obtiene Gastos (CORREGIDO: Agregamos table_name) */
  async getRawExpensesForReport(): Promise<any[]> {
    return this.fetchData('hotel_expenses');
  }

  /* Helper genérico blindado */
  private async fetchData(table: string): Promise<any[]> {
    try {
      const res: any = await lastValueFrom(
        this.http.post(`${this.apiUrl_crud}/${table}`, {
          operation: 'getall',
          table_name: table, // 👈 ESTO FALTABA para que el backend responda
          fields: { id_company: 1 }
        }, { headers: this.adminService.getAuthHeaders() })
      );
      return Array.isArray(res?.data) ? res.data : [];
    } catch (e) {
      console.error(`Error fetching ${table}`, e);
      return [];
    }
  }
}