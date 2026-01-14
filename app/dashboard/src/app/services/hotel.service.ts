import { Injectable, computed, inject, signal } from '@angular/core';
import { HttpClient, HttpHeaders } from '@angular/common/http';
import { Company, Room, User } from '../models/hotel.types';
import { environment } from '../../environments/environment';
import { ApiResponse } from '../interfaces/api-response.interface';

@Injectable({ providedIn: 'root' })
export class HotelService {
  private http = inject(HttpClient);
  private apiUrl_crud = environment.apiUrl_crud; // Tu URL de n8n
  public loading = signal<boolean>(false); // Nuevo Signal
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
    const token = localStorage.getItem('authToken');
    if (!token) {
      console.warn('⚠️ Abortando carga: No hay token disponible aún.');
      return;
    }
    this.loading.set(true);
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
          this.loading.set(false);
        },
        error: (err) => {
          console.error('Error de red o servidor:', err);
          this.rooms.set([]);
          this.loading.set(false);
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
        this.loading.set(false);
      },
      error: (err) => {
        console.error('Error en API:', err);
        this.companies.set([]); // Reset en caso de fallo
        this.loading.set(false)
      }
    });
  }

  // Companies
  loadUsers(id_company?: number) {
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
        this.loading.set(false);
      },
      error: (err) => {
        console.error('Error en API:', err);
        this.users.set([]); // Reset en caso de fallo
        this.loading.set(false)
      }
    });
  }

  // hotel.service.ts - Añade estos métodos

  /** Guarda o actualiza un usuario */
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
}