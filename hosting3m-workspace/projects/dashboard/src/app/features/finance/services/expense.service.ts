import { HttpClient } from '@angular/common/http';
import { inject, Injectable, signal } from '@angular/core';
import { environment } from '@env/environment';
import { AdminService } from '@features/admin/services/admin.service';
import { lastValueFrom } from 'rxjs';
import { Expense } from '../models/expense.model';
import { ApiResponse } from '@core/interfaces/api-response.interface';

@Injectable({
  providedIn: 'root'
})
export class ExpenseService {
  private http = inject(HttpClient);
  private adminService = inject(AdminService);
  private apiUrl = environment.apiUrl_crud;

  public loading = signal<boolean>(false);

  /** Obtener lista de gastos con filtros opcionales */
  async getExpenses(startDate?: string, endDate?: string): Promise<Expense[]> {
    this.loading.set(true);
    try {
      // Filtros dinámicos para el JSONB del backend
      const filters: any = {};
      if (startDate && endDate) {
        filters.expense_date = { gte: startDate, lte: endDate };
      }

      const payload = {
        operation: 'getall',
        table_name: 'hotel_expenses',
        filters: filters,
        // Ordenar por fecha descendente
        sort: { field: 'expense_date', order: 'DESC' }
      };

      const res = await lastValueFrom(
        this.http.post<ApiResponse<Expense>>(`${this.apiUrl}/hotel_expenses`, payload, {
          headers: this.adminService.getAuthHeaders()
        })
      );

      return Array.isArray(res.data) ? res.data : [];
    } catch (error) {
      console.error('Error cargando gastos', error);
      return [];
    } finally {
      this.loading.set(false);
    }
  }

  /** Registrar un nuevo gasto */
  async createExpense(expense: Partial<Expense>): Promise<void> {
    this.loading.set(true);
    try {
      const payload = {
        operation: 'insert',
        table_name: 'hotel_expenses',
        fields: {
          ...expense,
          id_company: 1, // Multi-tenancy hardcoded por ahora
          status: 'APPROVED' // Auto-aprobado si lo hace el admin
        }
      };

      await lastValueFrom(
        this.http.post(`${this.apiUrl}/hotel_expenses`, payload, {
          headers: this.adminService.getAuthHeaders()
        })
      );
    } catch (error) {
      console.error('Error creando gasto', error);
      throw error;
    } finally {
      this.loading.set(false);
    }
  }
}