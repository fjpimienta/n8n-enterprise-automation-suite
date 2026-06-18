import { Injectable, inject, signal } from '@angular/core';
import { HttpClient, HttpHeaders } from '@angular/common/http';
import { lastValueFrom, retry, catchError, of } from 'rxjs'; // 🚀 FIX: Importamos catchError y of
import { ApiResponse } from '@core/interfaces/api-response.interface';
import { environment } from '@env/environment';
import { Company } from '@core/models/company.model';
import { User } from '@core/models/user.model';
import { Guest } from '@core/models/guest.model';
import { TenantService } from 'core-auth';

@Injectable({
  providedIn: 'root',
})
export class AdminService {
  private http = inject(HttpClient);
  private apiUrl_crud = environment.apiUrl_crud;
  private tenantService = inject(TenantService);
  public loadingUsers = signal<boolean>(false);
  public loadingGuests = signal<boolean>(false);
  public users = signal<User[]>([]);
  public guests = signal<Guest[]>([]);
  public companies = signal<Company[]>([]);
  public loadingCompanies = signal<boolean>(false);
  public loadingReservations = signal<boolean>(false);

  public reservations = signal<any[]>([]);

  /* Headers con token de autenticación */
  private getHeaders() {
    return new HttpHeaders({ 'Authorization': `Bearer ${localStorage.getItem('authToken')}` });
  }

  /* Método para obtener los headers con el token de autenticación */
  public getAuthHeaders() {
    const token = localStorage.getItem('authToken');
    return new HttpHeaders({
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${token}`
    });
  }

  /* Companies Refactorizado: Blindaje contra nulos y errores de red */
  public loadCompanies() {
    this.loadingCompanies.set(true);

    // Verificación temprana: Si no hay token, no intentamos hacer la petición
    // para evitar saturar el backend con errores 401 obvios.
    if (!localStorage.getItem('authToken')) {
      console.warn('⚠️ loadCompanies cancelado: No hay token de autenticación disponible.');
      this.companies.set([]);
      this.loadingCompanies.set(false);
      return;
    }

    const payload = {
      entity: 'companys',
      table_name: 'companys',
      operation: 'getall',
      action: 'list',
      filters: {}
    };

    this.http.post<ApiResponse<Company>>(`${this.apiUrl_crud}/companys`, payload, {
      headers: this.getAuthHeaders()
    }).pipe(
      // 🛡️ Capturamos el error a nivel de flujo de RxJS
      catchError(error => {
        console.warn('⚠️ No se pudo cargar el catálogo de empresas:', error.message || error);
        // Retornamos un objeto "seguro" para que el subscribe no reviente
        return of({ status: 'error', data: [] } as any);
      })
    ).subscribe({
      next: (res) => {
        // 🛡️ Validación estricta de estructura antes de iterar
        if (res && Array.isArray(res.data)) {
          const sortedCompanies = res.data.sort((a: Company, b: Company) => {
            return String(a.id_company).localeCompare(String(b.id_company), undefined, { numeric: true });
          });
          this.companies.set(sortedCompanies);
        } else {
          this.companies.set([]);
        }
        this.loadingCompanies.set(false);
      },
      error: (err) => {
        // Este bloque ahora solo atrapará errores muy atípicos no cubiertos por catchError
        console.error('❌ Error no controlado en loadCompanies:', err);
        this.companies.set([]);
        this.loadingCompanies.set(false);
      }
    });
  }

  /* Users */
  public loadUsers() {
    const currentTenantId = this.tenantService.activeTenantId();
    this.loadingUsers.set(true);
    const payload = {
      entity: 'users',
      table_name: 'users',
      operation: 'getall',
      action: 'list',
      filters: { tenant_id: Number(currentTenantId) }
    };
    this.http.post<ApiResponse<User>>(`${this.apiUrl_crud}/users`, payload, {
      headers: this.getAuthHeaders()
    }).subscribe({
      next: (res) => {
        const data = Array.isArray(res.data) ? res.data : [];

        const validData = data.filter(u => u && u.email && u.email.trim() !== '');

        const sortedUsers = validData.sort((a, b) => {
          return (a.email || '').localeCompare(b.email || '');
        });

        this.users.set(sortedUsers);
        this.loadingUsers.set(false);
      },
      error: (err) => {
        console.error('Error en API:', err);
        this.users.set([]);
        this.loadingUsers.set(false);
      }
    });
  }

  /* Guardar o actualizar usuario */
  public saveUser(user: Partial<User>, operation: 'insert' | 'update', email?: string) {
    const payload = {
      entity: 'users',
      table_name: 'users',
      operation: operation,
      email: email,
      fields: user
    };

    return this.http.post<ApiResponse<User>>(`${this.apiUrl_crud}/users`, payload, {
      headers: this.getAuthHeaders()
    });
  }

  /* Guarda los cambios de un huésped (nuevo o editado) */
  /* Genera un ID interno único si no hay documento */
  public generateInternalId(): string {
    return `INT-${Date.now()}`;
  }

  /* Genera un email ficticio único si es necesario */
  public generateDummyEmail(): string {
    return `no-email-${Date.now()}@hosting3m.com`;
  }

}