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

    filteredBookings.forEach((b: any) => {
      b.payment_status = String(b.payment_status || '').trim().toLowerCase();

      const amount = Number(b.total_amount) || 0;

      if (b.payment_status === 'paid') {
        stats.paid_in += amount;
      } else {
        stats.pending += amount;
      }
    });

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
        if (!customStart || !customEnd) return false;
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

  // 1. NUEVO MÉTODO: Calcula las fechas exactas de inicio y fin del periodo
  public getPeriodDates(filter: string, customStart?: string, customEnd?: string): { start: string, end: string } {
    const now = new Date();
    const mxNow = new Date(now.toLocaleString("en-US", { timeZone: "America/Mexico_City" }));
    const todayStr = `${mxNow.getFullYear()}-${String(mxNow.getMonth() + 1).padStart(2, '0')}-${String(mxNow.getDate()).padStart(2, '0')}`;

    let start = todayStr; let end = todayStr;

    switch (filter) {
      case 'week':
        const startOfWeek = new Date(mxNow);
        startOfWeek.setDate(mxNow.getDate() - mxNow.getDay());
        start = `${startOfWeek.getFullYear()}-${String(startOfWeek.getMonth() + 1).padStart(2, '0')}-${String(startOfWeek.getDate()).padStart(2, '0')}`;
        break;
      case 'month':
        start = `${mxNow.getFullYear()}-${String(mxNow.getMonth() + 1).padStart(2, '0')}-01`;
        const lastDay = new Date(mxNow.getFullYear(), mxNow.getMonth() + 1, 0);
        end = `${lastDay.getFullYear()}-${String(lastDay.getMonth() + 1).padStart(2, '0')}-${String(lastDay.getDate()).padStart(2, '0')}`;
        break;
      case 'year':
        start = `${mxNow.getFullYear()}-01-01`;
        end = `${mxNow.getFullYear()}-12-31`;
        break;
      case 'custom':
        start = customStart || todayStr;
        end = customEnd || todayStr;
        break;
    }
    return { start, end };
  }

  // 2. MODIFICAMOS LAS PETICIONES PARA EXIGIR FECHAS
  async getRawBookingsForReport(start: string, end: string): Promise<any[]> {
    return this.fetchData('hotel_bookings', 'check_in', start, end);
  }

  async getRawExpensesForReport(start: string, end: string): Promise<any[]> {
    return this.fetchData('hotel_expenses', 'expense_date', start, end);
  }

  // 3. INYECTAMOS EL RANGO EN EL PAYLOAD PARA n8n
  private async fetchData(table: string, dateColumn: string, startDate: string, endDate: string): Promise<any[]> {
    try {
      const payload = {
        operation: 'getall',
        table_name: table,
        fields: { id_company: 1 },
        date_range: {
          column: dateColumn,
          start: startDate,
          end: endDate
        }
      };

      const res: any = await lastValueFrom(
        this.http.post(`${this.apiUrl_crud}/${table}`, payload, { headers: this.adminService.getAuthHeaders() })
      );
      return Array.isArray(res?.data) ? res.data : [];
    } catch (e) {
      console.error(`Error fetching ${table}`, e);
      return [];
    }
  }


}