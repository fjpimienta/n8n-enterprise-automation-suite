import { Injectable, inject, signal } from '@angular/core';
import { HttpClient, HttpHeaders } from '@angular/common/http';
import { ApiResponse } from '@core/interfaces/api-response.interface';
import { Company, Guest, Room, User } from '@core/models/hotel.types';
import { environment } from '@env/environment';

@Injectable({
  providedIn: 'root',
})
export class AdminService {
  private http = inject(HttpClient);
  private apiUrl_crud = environment.apiUrl_crud;

  public loadingUsers = signal<boolean>(false);
  public loadingGuests = signal<boolean>(false);
  public loadingCompanies = signal<boolean>(false);
  public loadingReservations = signal<boolean>(false);

  users = signal<User[]>([]);
  guests = signal<Guest[]>([]);
  public reservations = signal<any[]>([]);
  companies = signal<Company[]>([]);
  selectedUser = signal<User | null>(null);

  /* Headers con token de autenticación */
  private getHeaders() {
    return new HttpHeaders({ 'Authorization': `Bearer ${localStorage.getItem('authToken')}` });
  }

  /* Método para obtener los headers con el token de autenticación */
  public getAuthHeaders() {
    const authToken = localStorage.getItem('authToken'); // O de donde guardes tu JWT
    return new HttpHeaders({
      'Authorization': `Bearer ${authToken}`
    });
  }

  /* Companies */
  public loadCompanies() {
    this.loadingCompanies.set(true);
    const payload = {
      entity: 'companys',
      table_name: 'companys',
      operation: 'getall',
      action: 'list',
      filters: {}
    };
    this.http.post<ApiResponse<Company>>(`${this.apiUrl_crud}/companys`, payload, {
      headers: this.getAuthHeaders()
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

  /* Reservations */
  public loadReservations() {
    this.loadingReservations.set(true);

    const payload = {
      entity: 'hotel_bookings',
      table_name: 'hotel_bookings',
      operation: 'getall',
      action: 'list',
      filters: {
        status: 'confirmed' // Solo nos interesan las que no se han cancelado ni terminado
      }
    };

    this.http.post<ApiResponse<any>>(`${this.apiUrl_crud}/hotel_bookings`, payload, {
      headers: this.getAuthHeaders()
    }).subscribe({
      next: (res) => {
        if (res && !res.error && res.data) {
          this.reservations.set(res.data);
        } else {
          this.reservations.set([]);
        }
        this.loadingReservations.set(false);
      },
      error: (err) => {
        console.error('Error cargando reservas:', err);
        this.reservations.set([]);
        this.loadingReservations.set(false);
      }
    });
  }

  /* Users */
  public loadUsers(id_company?: number) {
    this.loadingUsers.set(true);
    const payload = {
      entity: 'users',
      table_name: 'users',
      operation: 'getall',
      action: 'list',
      filter: { id_company: id_company }
    };
    this.http.post<ApiResponse<User>>(`${this.apiUrl_crud}/users`, payload, {
      headers: this.getAuthHeaders()
    }).subscribe({
      next: (res) => {
        const data = Array.isArray(res.data) ? res.data : [];
        const validData = data.filter(g => g && g.email && g.email.trim() !== '');
        const sortedUsers = validData.sort((a, b) => {
          return (a.email || '').localeCompare(b.email || '');
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

  /* Guardar o actualizar usuario */
  public saveUser(user: Partial<User>, operation: 'insert' | 'update', email?: string) {
    const payload = {
      entity: 'users',
      table_name: 'users',
      operation: operation,
      email: email, // Solo para update
      fields: user
    };

    return this.http.post<ApiResponse<User>>(`${this.apiUrl_crud}/users`, payload, {
      headers: this.getAuthHeaders()
    });
  }

  /* Guests */
  public loadGuests(id_company?: number) {
    this.loadingGuests.set(true);

    const payload = {
      entity: 'hotel_guests',
      table_name: 'hotel_guests',
      operation: 'getall',
      action: 'list',
      filter: { id_company: id_company }
    };

    this.http.post<ApiResponse<Guest>>(`${this.apiUrl_crud}/hotel_guests`, payload, {
      headers: this.getAuthHeaders()
    }).subscribe({
      next: (res) => {
        const rawData = Array.isArray(res.data) ? res.data : [];
        const allGuests = rawData.filter(g => g);
        const sortedGuests = allGuests.sort((a, b) => {
          const nameA = a.full_name || '';
          const nameB = b.full_name || '';
          return nameA.localeCompare(nameB);
        });
        this.guests.set(sortedGuests);
        this.loadingGuests.set(false);
      },
      error: (err) => {
        console.error('Error en API:', err);
        this.guests.set([]);
        this.loadingGuests.set(false);
      }
    });
  }

  /* Guarda los cambios de un huésped (nuevo o editado) */
  /* Genera un ID interno único si no hay documento */
  public generateInternalId(): string {
    // Retorna algo como: INT-1706289452123 (INT + Timestamp en milisegundos)
    return `INT-${Date.now()}`;
  }

  /* Genera un email ficticio único si es necesario */
  public generateDummyEmail(): string {
    // Retorna: no-email-1706289452123@hosting3m.com
    return `no-email-${Date.now()}@hosting3m.com`;
  }

  /* Guardar o actualizar huésped */
  public saveGuest(guest: Partial<Guest>, operation: 'insert' | 'update', email?: string) {
    console.log('guests: ', guest);
    let finalDocId = guest.doc_id;
    if (!finalDocId || finalDocId.trim() === '') {
      finalDocId = this.generateInternalId();
    }
    let finalEmail = guest.email;
    if (!finalEmail || finalEmail.trim() === '') {
      finalEmail = this.generateDummyEmail();
    }
    guest.email= finalEmail;
    guest.doc_id= finalDocId;
    const payload = {
      entity: 'hotel_guests',
      table_name: 'hotel_guests',
      operation: operation,
      email: email, // Solo para update
      fields: guest
    };
    return this.http.post<ApiResponse<Guest>>(`${this.apiUrl_crud}/hotel_guests`, payload, {
      headers: this.getAuthHeaders()
    });
  }

}