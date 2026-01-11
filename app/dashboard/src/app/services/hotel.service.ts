import { Injectable, computed, inject, signal } from '@angular/core';
import { HttpClient, HttpHeaders } from '@angular/common/http';
import { Room } from '../models/hotel.types';
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
    this.loading.set(true); // Empezamos carga
    const payload = {
      entity: 'hotel_rooms',
      table_name: 'hotel_rooms',
      operation: 'getall',
      action: 'list',
      filters: {}
    };

    // 1. Tipamos el post con <ApiResponse<Room>>
    this.http.post<ApiResponse<Room>>(`${this.apiUrl_crud}/${payload.entity}`, payload, {
      headers: this.getAuthHeaders()
    })
      .subscribe({
        next: (res) => {
          // 2. Gracias a la interfaz, TS sabe que res.data es un Room[]
          const data = res.data || [];
          // Ordenamos antes de setear el estado
          const sortedRooms = data.sort((a, b) => {
            // Usamos numeric: true para que ordene 1, 2, 10 en lugar de 1, 10, 2
            return String(a.room_number).localeCompare(String(b.room_number), undefined, { numeric: true });
          });
          this.rooms.set(sortedRooms);
          this.loading.set(false);
        },
        error: (err) => {
          console.error('Error en API:', err);
          this.rooms.set([]); // Reset en caso de fallo
          this.loading.set(false)
        }
      });
  }

  // Método rápido para Housekeeping
  updateRoomStatus(id: number, status: string) {
    const payload = {
      entity: 'hotel_rooms',
      table_name: 'hotel_rooms',
      action: 'update',
      id: id,
      fields: { cleaning_status: status }
    };
    return this.http.post(`${this.apiUrl_crud}/${payload.entity}`, payload, {
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

}