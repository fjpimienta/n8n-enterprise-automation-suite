import { Injectable, inject, signal } from '@angular/core';
import { HttpClient, HttpHeaders } from '@angular/common/http';
import { lastValueFrom } from 'rxjs';
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
    const authToken = localStorage.getItem('authToken');
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
        const data = res.data || [];
        const sortedCompanies = data.sort((a, b) => {
          return String(a.id_company).localeCompare(String(b.id_company), undefined, { numeric: true });
        });
        this.companies.set(sortedCompanies);
        this.loadingCompanies.set(false);
      },
      error: (err) => {
        console.error('Error en API:', err);
        this.companies.set([]);
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
      filters: {}
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

        const allGuests = rawData.filter(g => g && g.id);

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

  checkPossibleDuplicate(fullName: string) {
    const payload = {
      operation: 'getall',
      table_name: 'hotel_guests',
      filters: {
        full_name: fullName
      }
    };
    const data = this.http.post<ApiResponse<any>>(`${this.apiUrl_crud}/hotel_guests`, payload, {
      headers: this.getAuthHeaders()
    });
    return data;
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

  /**
   * Guarda o actualiza un huésped realizando validaciones de duplicados y normalización de datos.
   * @param guest Datos del huésped.
   * @param selectedGuest Huésped seleccionado previamente (si es edición).
   */
  public async saveGuestWithValidation(guest: Partial<Guest>, selectedGuest?: Guest | null): Promise<ApiResponse<Guest>> {
    const currentName = guest.full_name || '';
    const operation = selectedGuest ? 'update' : 'insert';

    // 1. Validación de Duplicados (Solo para nuevos registros)
    if (!selectedGuest) {
      const duplicates = await lastValueFrom(this.checkPossibleDuplicate(currentName));
      if (duplicates.data && duplicates.data.length > 0) {
        const confirm = window.confirm(
          `⚠️ Encontramos ${duplicates.data.length} persona(s) con el nombre "${currentName}".\n\n` +
          `¿Estás SEGURO que es una persona diferente?\n` +
          `(Acepta para crear uno NUEVO, Cancela para revisar los existentes)`
        );
        if (!confirm) {
          throw new Error('OPERACION_CANCELADA_POR_DUPLICADO');
        }
      }
    }

    // 2. Normalización de DOC_ID
    let finalDocId = guest.doc_id;
    if (!finalDocId || finalDocId.trim() === '') {
      if (selectedGuest && selectedGuest.doc_id && selectedGuest.doc_id.startsWith('INT-')) {
        finalDocId = selectedGuest.doc_id;
      } else {
        finalDocId = this.generateInternalId();
      }
    }

    // 3. Normalización de EMAIL
    let finalEmail = guest.email;
    if (!finalEmail || finalEmail.trim() === '') {
      if (selectedGuest && selectedGuest.email && selectedGuest.email.includes('no-email-')) {
        finalEmail = selectedGuest.email;
      } else {
        finalEmail = this.generateDummyEmail();
      }
    }

    const guestPayload = {
      ...guest,
      doc_id: finalDocId,
      email: finalEmail
    };

    const payload = {
      entity: 'hotel_guests',
      table_name: 'hotel_guests',
      operation: operation,
      fields: guestPayload
    };

    return await lastValueFrom(
      this.http.post<ApiResponse<Guest>>(`${this.apiUrl_crud}/hotel_guests`, payload, {
        headers: this.getAuthHeaders()
      })
    );
  }

  /* Crea un nuevo huésped envolviendo saveGuest en una Promesa */
  public async createGuest(guest: Partial<Guest>) {
    return await lastValueFrom(this.saveGuest(guest, 'insert'));
  }

  /* Actualiza un huésped existente */
  public async updateGuest(guest: Partial<Guest>) {
    return await lastValueFrom(this.saveGuest(guest, 'update', guest.email));
  }

  /* Guardar o actualizar huésped (Legacy) */
  public saveGuest(guest: Partial<Guest>, operation: 'insert' | 'update', email?: string) {
    let finalDocId = guest.doc_id;
    if (!finalDocId || finalDocId.trim() === '') {
      finalDocId = this.generateInternalId();
    }
    let finalEmail = guest.email;
    if (!finalEmail || finalEmail.trim() === '') {
      finalEmail = this.generateDummyEmail();
    }
    guest.email = finalEmail;
    guest.doc_id = finalDocId;
    const payload = {
      entity: 'hotel_guests',
      table_name: 'hotel_guests',
      operation: operation,
      email: email,
      fields: guest
    };
    return this.http.post<ApiResponse<Guest>>(`${this.apiUrl_crud}/hotel_guests`, payload, {
      headers: this.getAuthHeaders()
    });
  }

}