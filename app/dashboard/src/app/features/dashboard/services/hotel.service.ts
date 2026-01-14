import { Injectable, computed, inject, signal } from '@angular/core';
import { HttpClient, HttpHeaders } from '@angular/common/http';
import { ApiResponse } from '@core/interfaces/api-response.interface';
import { Company, Room, User } from '@core/models/hotel.types';
import { environment } from '@env/environment';
import { lastValueFrom } from 'rxjs';

@Injectable({ providedIn: 'root' })
export class HotelService {
  private http = inject(HttpClient);
  private apiUrl_crud = environment.apiUrl_crud;
  public loadingRooms = signal<boolean>(false);
  public loadingUsers = signal<boolean>(false);
  public loadingReports = signal<boolean>(false);
  public loadingCompanies = signal<boolean>(false);
  filter = signal<'all' | 'available' | 'occupied' | 'checkout' | 'maintenance'>('available');

  // Signal para estado reactivo (Best Practice Angular 19+)
  rooms = signal<Room[]>([]);
  selectedRoom = signal<Room | null>(null); // Habitación para el detalle
  companies = signal<Company[]>([]);
  selectedCompany = signal<Company | null>(null); // Empresa para el detalle
  users = signal<User[]>([]);
  selectedUser = signal<User | null>(null); // Usuario para el detalle

  // Creamos un Signal computado para obtener solo las habitaciones que coinciden
  filteredRooms = computed(() => {
    const rooms = this.rooms();
    const currentFilter = this.filter();

    switch (currentFilter) {
      case 'available':
        // Una habitación es vendible solo si está 'available' Y 'clean' o 'inspected'
        return rooms.filter(r =>
          r.status === 'available' && (r.cleaning_status === 'clean' || r.cleaning_status === 'inspected')
        );
      case 'occupied':
        return rooms.filter(r => r.status === 'occupied');
      case 'checkout':
        // Urge limpiar: está libre pero sigue sucia
        return rooms.filter(r => r.status === 'available' && r.cleaning_status === 'dirty');
      case 'maintenance':
        return rooms.filter(r => r.status === 'maintenance');
      default:
        return rooms;
    }
  });

  // Función auxiliar para obtener los headers con el authToken
  private getAuthHeaders() {
    const authToken = localStorage.getItem('authToken'); // O de donde guardes tu JWT
    return new HttpHeaders({
      'Authorization': `Bearer ${authToken}`
    });
  }

  loadRooms() {
    this.loadingRooms.set(true);
    const token = localStorage.getItem('authToken');
    if (!token) {
      console.warn('⚠️ Abortando carga: No hay token disponible aún.');
      return;
    }
    const payloadRoom = {
      entity: 'hotel_rooms',
      table_name: 'hotel_rooms',
      operation: 'getall',
      action: 'list',
      filters: {}
    };

    this.http.post<ApiResponse<Room>>(`${this.apiUrl_crud}/${payloadRoom.table_name}`, payloadRoom, {
      headers: this.getAuthHeaders()
    })
      .subscribe({
        next: (res) => {
          // VALIDACIÓN CRÍTICA: Verificamos que res y res.data existan
          if (res && !res.error && res.data) {
            const data = Array.isArray(res.data) ? res.data : [];
            const sortedRooms = [...data].sort((a, b) =>
              String(a.room_number).localeCompare(String(b.room_number), undefined, { numeric: true })
            );
            this.rooms.set(sortedRooms);
          } else {
            // Si n8n devuelve error pero entra por 'next' (status 200 con error JSON)
            console.error('Respuesta de API no exitosa:', res);
            this.rooms.set([]);
          }
          this.loadingRooms.set(false);
        },
        error: (err) => {
          console.error('Error de red o servidor:', err);
          this.rooms.set([]);
          this.loadingRooms.set(false);
        }
      });
  }

  // Método rápido para Housekeeping
  updateRoomStatus(id: number, status: string) {
    const payloadRoom = {
      entity: 'hotel_rooms',
      table_name: 'hotel_rooms',
      action: 'update',
      id: id,
      fields: { cleaning_status: status }
    };
    return this.http.post(`${this.apiUrl_crud}/${payloadRoom.table_name}`, payloadRoom, {
      headers: this.getAuthHeaders()
    });
  }

  // Función para seleccionar
  selectRoom(room: Room) {
    this.selectedRoom.set(room);
  }

  // Función para cerrar detalle
  clearSelection() {
    this.selectedRoom.set(null);
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

  loadUsers(id_company?: number) {
    this.loadingUsers.set(true);
    const payloadUsers = {
      entity: 'users',
      table_name: 'users',
      operation: 'getall',
      action: 'list',
      filter: { id_company: id_company }
    };
    this.http.post<ApiResponse<User>>(`${this.apiUrl_crud}/${payloadUsers.table_name}`, payloadUsers, {
      headers: this.getAuthHeaders()
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
      headers: this.getAuthHeaders()
    });
  }

  /** Selecciona un usuario para editarlo */
  selectUser(user: User | null) {
    this.selectedUser.set(user);
  }





  /**
   * Obtiene la reserva activa de una habitación
   */
  async getActiveBooking(roomId: number): Promise<any> {
    const payload = {
      operation: 'getall',
      fields: { room_id: roomId, status: 'confirmed' }
    };
    const res = await lastValueFrom(
      this.http.post<ApiResponse<any>>(`${this.apiUrl_crud}/hotel_bookings`, payload, { headers: this.getAuthHeaders() })
    );
    return res.data && res.data.length > 0 ? res.data[0] : null;
  }



  /**
   * PROCESO COMPLETO DE CHECK-IN
   * Centraliza: Insertar Huésped -> Crear Reserva -> Ocupar Habitación
   */
  async processCheckin(formData: any, room: Room): Promise<void> {
    const crudUrl = this.apiUrl_crud;

    // 1. Insertar Huésped (Deducción de ID automática)
    const guestRes: any = await lastValueFrom(
      this.http.post(`${crudUrl}/hotel_guests`, {
        operation: 'insert',
        fields: {
          full_name: formData.full_name,
          phone: formData.phone,
          doc_id: formData.doc_id,
          id_company: 1, // O usar this.authService.currentUser()?.id_company
          email: formData.email || null,
          country: formData.country || 'México'
        }
      }, { headers: this.getAuthHeaders() })
    );

    const guestId = guestRes?.data?.[0]?.id || guestRes?.id || guestRes?.data?.id;
    if (!guestId) throw new Error("No se pudo recuperar el ID del huésped");

    // 2. Crear la Reserva
    await lastValueFrom(
      this.http.post(`${crudUrl}/hotel_bookings`, {
        operation: 'insert',
        fields: {
          room_id: room.id,
          guest_id: guestId,
          check_in: formData.check_in || new Date().toISOString(),
          check_out: formData.check_out,
          total_amount: formData.total_amount || 0,
          status: 'confirmed',
          payment_status: 'pending',
          id_company: 1
        }
      }, { headers: this.getAuthHeaders() })
    );

    // 3. Cambiar estado de la Habitación a Ocupada
    await lastValueFrom(
      this.http.post(`${crudUrl}/hotel_rooms`, {
        operation: 'update', // Usamos insert para el Upsert de tu API
        fields: {
          id: room.id,
          status: 'occupied',
          cleaning_status: 'clean'
        }
      }, { headers: this.getAuthHeaders() })
    );
  }

  /**
   * PROCESO DE CHECK-OUT
   * Finaliza la reserva y deja la habitación sucia para limpieza
   */
  async processCheckout(room: Room, bookingId: number, inventoryReport: string, checks: any): Promise<void> {
    const crudUrl = this.apiUrl_crud;

    // 1. Actualizar Reserva a Finalizada
    await lastValueFrom(
      this.http.post(`${crudUrl}/hotel_bookings`, {
        operation: 'update',
        id: bookingId,
        fields: {
          status: 'checked_out',
          check_out: new Date().toISOString(),
          notes: inventoryReport,
          inventory_tv_ok: checks.tvRemote,
          inventory_ac_ok: checks.acRemote,
          inventory_keys_ok: checks.keys
        }
      }, { headers: this.getAuthHeaders() })
    );

    // 2. Liberar habitación pero marcar como Sucia
    await lastValueFrom(
      this.http.post(`${crudUrl}/hotel_rooms`, {
        operation: 'update',
        id: room.id,
        fields: {
          status: 'available',
          cleaning_status: 'dirty'
        }
      }, { headers: this.getAuthHeaders() })
    );
  }


  /**
   * Registra el pago de una reserva
   */
  async registerPayment(bookingId: number): Promise<void> {
    await lastValueFrom(
      this.http.post(`${this.apiUrl_crud}/hotel_bookings`, {
        operation: 'update',
        id: bookingId,
        fields: { payment_status: 'paid' }
      }, { headers: this.getAuthHeaders() })
    );
  }

  /**
     * Obtiene todas las reservas para procesamiento de reportes
     */
  async getRawBookingsForReport(): Promise<any[]> {
    this.loadingReports.set(true);
    try {
      const res: any = await lastValueFrom(
        this.http.post(`${this.apiUrl_crud}/hotel_bookings`, {
          operation: 'getall',
          fields: { id_company: 1 }
        }, { headers: this.getAuthHeaders() })
      );
      return Array.isArray(res?.data) ? res.data : [];
    } finally {
      this.loadingReports.set(false);
    }
  }

}