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

  /** Convierte fecha UTC de BD a YYYY-MM-DD exacto en hora local de México */
  private toLocalDate(dateStr: string): string {
    if (!dateStr) return '';
    // Forzamos que JS entienda que es UTC agregando la 'Z' si no la trae
    const cleanStr = dateStr.trim().replace(' ', 'T');
    const dateObj = new Date(cleanStr.includes('Z') || cleanStr.includes('+') ? cleanStr : cleanStr + 'Z');

    // Extraemos la fecha ya convertida al reloj local de la computadora
    const year = dateObj.getFullYear();
    const month = String(dateObj.getMonth() + 1).padStart(2, '0');
    const day = String(dateObj.getDate()).padStart(2, '0');

    return `${year}-${month}-${day}`;
  }

  /** * Calcula el reporte unificado (Ventas - Gastos = Balance) 
   * Acepta 'bookings' Y 'expenses'
   */
  // 1. Agrega customStart y customEnd a los parámetros, y 'custom' al tipo de filtro
  calculateDailyReport(
    bookings: any[],
    expenses: any[],
    filter: 'day' | 'week' | 'month' | 'year' | 'custom',
    customStart?: string,
    customEnd?: string,
    incomeBillingFilter: string = 'Todos',
    expensePaymentFilter: string = 'Todos'
  ) {
    const now = new Date();
    const mxNow = now.toLocaleString("en-US", { timeZone: "America/Mexico_City" });
    const nowObj = new Date(mxNow);
    const todayStr = `${nowObj.getFullYear()}-${String(nowObj.getMonth() + 1).padStart(2, '0')}-${String(nowObj.getDate()).padStart(2, '0')}`;

    const filteredBookings = bookings.filter((b: any) => {
      const dateMatch = this.isDateInPeriod(b.check_in, filter, nowObj, todayStr, customStart, customEnd);
      if (!dateMatch) return false;

      // Lógica del filtro de facturación
      if (incomeBillingFilter === 'Facturado') return b.is_invoiced === true;
      if (incomeBillingFilter === 'No Facturado') return !b.is_invoiced;
      return true;
    });

    const filteredExpenses = expenses.filter((e: any) => {
      const dateMatch = e.status === 'APPROVED' && this.isDateInPeriod(e.expense_date, filter, nowObj, todayStr, customStart, customEnd);
      if (!dateMatch) return false;

      // Lógica del filtro de método de pago
      if (expensePaymentFilter !== 'Todos') return e.payment_method === expensePaymentFilter;
      return true;
    });

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
    filteredBookings.forEach((b: any) => {
      // Limpiamos la variable para evitar errores de espacios
      b.payment_status = String(b.payment_status || '').trim().toLowerCase();

      const amount = Number(b.total_amount) || 0;

      if (b.payment_status === 'paid') {
        stats.paid_in += amount;
      } else {
        stats.pending += amount;
      }
    });

    // Sumar Gastos
    filteredExpenses.forEach(e => {
      stats.total_expenses += parseFloat(e.amount || 0);
    });

    stats.balance = stats.paid_in - stats.total_expenses;
    return stats;
  }

  /* Lógica centralizada de fechas (Aquí está la magia de los filtros) */
  private isDateInPeriod(dateStr: string, filter: string, nowObj: Date, todayStr: string, customStart?: string, customEnd?: string): boolean {
    if (!dateStr) return false;
    const dateLocalStr = this.toLocalDate(dateStr);

    const cleanStr = dateStr.trim().replace(' ', 'T');
    const utcDate = new Date(cleanStr.includes('Z') || cleanStr.includes('+') ? cleanStr : cleanStr + 'Z');
    const dateObj = new Date(utcDate.toLocaleString("en-US", { timeZone: "America/Mexico_City" }));

    switch (filter) {
      case 'day': return dateLocalStr === todayStr;
      case 'week':
        const startOfWeek = new Date(nowObj);
        startOfWeek.setDate(nowObj.getDate() - nowObj.getDay());
        startOfWeek.setHours(0, 0, 0, 0);
        return dateObj >= startOfWeek;
      case 'month':
        return dateObj.getMonth() === nowObj.getMonth() && dateObj.getFullYear() === nowObj.getFullYear();
      case 'year':
        return dateObj.getFullYear() === nowObj.getFullYear();

      case 'custom':
        if (!customStart || !customEnd) return false; // Si falta una fecha, no mostramos nada
        return dateLocalStr >= customStart && dateLocalStr <= customEnd;

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
          table_name: table,
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