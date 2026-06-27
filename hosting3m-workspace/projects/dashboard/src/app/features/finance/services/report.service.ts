import { HttpClient } from '@angular/common/http';
import { inject, Injectable, signal } from '@angular/core';
import { environment } from '@env/environment';
import { AdminService } from '@features/admin/services/admin.service';
import { TenantService } from 'core-auth';
import { lastValueFrom } from 'rxjs';

@Injectable({
  providedIn: 'root',
})
export class ReportService {
  private http = inject(HttpClient);
  private apiUrl_crud = environment.apiUrl_crud;
  private tenantService = inject(TenantService);
  
  public loadingReports = signal<boolean>(false);
  public adminService = inject(AdminService);

  /** * Calcula el reporte unificado con Filtros Avanzados */
  calculateDailyReport(
    bookings: any[],
    expenses: any[],
    filter: 'day' | 'week' | 'month' | 'year' | 'custom',
    customStart?: string,
    customEnd?: string,
    incomeBillingFilter: string = 'Todos',
    expensePaymentFilter: string = 'Todos',
    incomeRoomFilter: string = 'Todos',
    incomeStatusFilter: string = 'Todos',
    incomePaymentFilter: string = 'Todos',
    expenseConceptFilter: string = '',
    expenseCategoryFilter: string = 'Todas'
  ) {
    const now = new Date();
    const mxNow = now.toLocaleString("en-US", { timeZone: "America/Mexico_City" });
    const nowObj = new Date(mxNow);
    const todayStr = `${nowObj.getFullYear()}-${String(nowObj.getMonth() + 1).padStart(2, '0')}-${String(nowObj.getDate()).padStart(2, '0')}`;

    const filteredBookings = bookings.filter((b: any) => {
      const dateMatch = this.isDateInPeriod(b.check_in, filter, nowObj, todayStr, customStart, customEnd);
      if (!dateMatch) return false;

      if (incomeBillingFilter === 'Facturado' && !b.is_invoiced) return false;
      if (incomeBillingFilter === 'No Facturado' && b.is_invoiced) return false;

      if (incomeRoomFilter !== 'Todos' && String(b.room_id) !== incomeRoomFilter) return false;
      if (incomePaymentFilter !== 'Todos' && b.payment_method !== incomePaymentFilter) return false;

      const isCancelled = b.status === 'cancelled';
      const isPaid = String(b.payment_status || '').trim().toLowerCase() === 'paid';

      if (incomeStatusFilter === 'Pagado' && (!isPaid || isCancelled)) return false;
      if (incomeStatusFilter === 'Pendiente' && (isPaid || isCancelled)) return false;
      if (incomeStatusFilter === 'Cancelado' && !isCancelled) return false;

      return true;
    });

    const filteredExpenses = expenses.filter((e: any) => {
      const dateMatch = e.status === 'APPROVED' && this.isDateInPeriod(e.expense_date, filter, nowObj, todayStr, customStart, customEnd);
      if (!dateMatch) return false;

      if (expensePaymentFilter !== 'Todos' && e.payment_method !== expensePaymentFilter) return false;
      if (expenseCategoryFilter !== 'Todas' && e.category !== expenseCategoryFilter) return false;

      if (expenseConceptFilter.trim() !== '') {
        const query = expenseConceptFilter.toLowerCase().trim();
        const desc = String(e.description || '').toLowerCase();
        if (!desc.includes(query)) return false;
      }

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
      if (b.status === 'cancelled') return; // 🛑 No sumar cancelaciones a los totales

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

  // 1. FIX MATEMÁTICO: Convertimos la hora UTC a Local antes de extraer el string
  private toLocalDate(dateStr: string): string {
    if (!dateStr) return '';

    const cleanStr = dateStr.trim().replace(' ', 'T');
    const finalStr = cleanStr.includes('Z') || cleanStr.includes('+') ? cleanStr : cleanStr + 'Z';

    // Al usar new Date(), forzamos a que el sistema aplique el UTC-6 (CST)
    const dateObj = new Date(finalStr);

    const year = dateObj.getFullYear();
    const month = String(dateObj.getMonth() + 1).padStart(2, '0');
    const day = String(dateObj.getDate()).padStart(2, '0');

    return `${year}-${month}-${day}`;
  }

  // 2. 🚀 FIX LÓGICO: Forzamos los cálculos al mediodía para evitar saltos de día
  private isDateInPeriod(dateStr: string, filter: string, nowObj: Date, todayStr: string, customStart?: string, customEnd?: string): boolean {
    if (!dateStr) return false;
    const dateLocalStr = this.toLocalDate(dateStr); // "2026-03-28"

    // Creamos la fecha a las 12:00 PM local para que soporte cálculos de semana/mes sin atrasarse
    const dateObj = new Date(`${dateLocalStr}T12:00:00`);

    switch (filter) {
      case 'day': return dateLocalStr === todayStr; // Comparación estricta de strings
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

  // 3. FIX VISUAL DEFINITIVO: Interceptamos JSON puro de API con Regex
  async getRawBookingsForReport(start: string, end: string): Promise<any[]> {
    const data = await this.fetchData('hotel_bookings', 'check_in', start, end);

    return data.map(b => {
      let ci = b.check_in ? String(b.check_in) : '';
      let co = b.check_out ? String(b.check_out) : '';

      // Usamos Regex para atrapar la medianoche exacta que viene de n8n o PostgreSQL
      if (ci.includes('T00:00:00') || ci.includes(' 00:00:00')) {
        b.check_in = ci.replace(/T00:00:00(\.000Z)?| 00:00:00(\+00)?/g, 'T15:00:00.000Z');
      }

      if (co.includes('T00:00:00') || co.includes(' 00:00:00')) {
        b.check_out = co.replace(/T00:00:00(\.000Z)?| 00:00:00(\+00)?/g, 'T18:00:00.000Z');
      }

      return b;
    });
  }

  private getPeriodLabel(filter: string): string {
    const labels: any = { 'day': 'Hoy', 'week': 'Esta Semana', 'month': 'Este Mes', 'year': 'Este Año' };
    return labels[filter] || 'Periodo';
  }

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

  async getRawExpensesForReport(start: string, end: string): Promise<any[]> {
    return this.fetchData('hotel_expenses', 'expense_date', start, end);
  }

  private async fetchData(table: string, dateColumn: string, startDate: string, endDate: string): Promise<any[]> {
    try {
      const payload = {
        operation: 'getall',
        table_name: table,
        fields: { id_company: this.tenantService.activeTenantId() },
        date_range: { column: dateColumn, start: startDate, end: endDate }
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

  // Agrega esto donde calculas tu reporte financiero
  async getCapitalTotal(): Promise<number> {
    try {
      // 🛠️ FIX: Usamos el mismo motor POST dinámico de tu backend (n8n/Supabase)
      const payload = {
        operation: 'getall',
        table_name: 'hotel_capital', // El model_name que registramos en BD
        fields: { id_company: this.tenantService.activeTenantId() }
      };

      const res: any = await lastValueFrom(
        this.http.post(`${this.apiUrl_crud}/hotel_capital`, payload, { headers: this.adminService.getAuthHeaders() })
      );

      const capitalList = Array.isArray(res?.data) ? res.data : [];

      // Sumamos todo el capital inyectado
      return capitalList.reduce((acc: number, curr: any) => acc + Number(curr.amount), 0);
    } catch (error) {
      console.error('Error cargando capital', error);
      return 0; // Fallback
    }
  }
}