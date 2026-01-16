import { Injectable, inject, signal } from '@angular/core';
import { HttpClient, HttpHeaders } from '@angular/common/http';
import { BookingService } from '@features/booking/services/booking.service';
import { ApiResponse } from '@core/interfaces/api-response.interface';
import { Company, User } from '@core/models/hotel.types';
import { environment } from '@env/environment';

@Injectable({
  providedIn: 'root',
})
export class AdminService {
  private http = inject(HttpClient);
  private apiUrl_crud = environment.apiUrl_crud;

  public bookingService = inject(BookingService);
  public loadingUsers = signal<boolean>(false);
  public loadingCompanies = signal<boolean>(false);

  users = signal<User[]>([]);
  companies = signal<Company[]>([]);
  selectedUser = signal<User | null>(null);

  private getHeaders() {
    return new HttpHeaders({ 'Authorization': `Bearer ${localStorage.getItem('authToken')}` });
  }

  // Companies
  loadCompanies() {
    this.loadingCompanies.set(true);
    const payloadCompanies = {
      entity: 'companys',
      table_name: 'companys',
      operation: 'getall',
      action: 'list',
      filters: {}
    };
    this.http.post<ApiResponse<Company>>(`${this.apiUrl_crud}/${payloadCompanies.table_name}`, payloadCompanies, {
      headers: this.bookingService.getAuthHeaders()
    }).subscribe({
      next: (res) => {
        // 2. Gracias a la interfaz, TS sabe que res.data es un Room[]
        const data = res.data || [];
        // Ordenamos antes de setear el estado
        const sortedCompanies = data.sort((a, b) => {
          // Usamos numeric: true para que ordene 1, 2, 10 en lugar de 1, 10, 2
          return String(a.id_company).localeCompare(String(b.id_company), undefined, { numeric: true });
        });
        this.companies.set(sortedCompanies);
        this.loadingCompanies.set(false);
      },
      error: (err) => {
        console.error('Error en API:', err);
        this.companies.set([]); // Reset en caso de fallo
        this.loadingCompanies.set(false)
      }
    });
  }

  // Users
  public loadUsers(id_company?: number) {
    this.loadingUsers.set(true);
    const payloadUsers = {
      entity: 'users',
      table_name: 'users',
      operation: 'getall',
      action: 'list',
      filter: { id_company: id_company }
    };
    this.http.post<ApiResponse<User>>(`${this.apiUrl_crud}/${payloadUsers.table_name}`, payloadUsers, {
      headers: this.bookingService.getAuthHeaders()
    }).subscribe({
      next: (res) => {
        const data = res.data || [];
        const sortedUsers = data.sort((a, b) => {
          return a.email.localeCompare(b.email);
        });
        this.users.set(sortedUsers);
        this.loadingUsers.set(false)
      },
      error: (err) => {
        console.error('Error en API:', err);
        this.users.set([]); // Reset en caso de fallo
        this.loadingUsers.set(false)
      }
    });
  }

  saveUser(user: Partial<User>, operation: 'insert' | 'update', email?: string) {
    const payload = {
      entity: 'users',
      table_name: 'users',
      operation: operation,
      email: email, // Solo para update
      fields: user
    };

    return this.http.post<ApiResponse<User>>(`${this.apiUrl_crud}/users`, payload, {
      headers: this.bookingService.getAuthHeaders()
    });
  }

}