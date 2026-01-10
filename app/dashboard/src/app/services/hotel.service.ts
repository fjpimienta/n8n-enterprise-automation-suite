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
  filter = signal<'all' | 'available' | 'occupied' | 'dirty'>('all');

  // Signal para estado reactivo (Best Practice Angular 19+)
  rooms = signal<Room[]>([]);
  selectedRoom = signal<Room | null>(null); // Habitación para el detalle

  // Creamos un Signal computado para obtener solo las habitaciones que coinciden
  filteredRooms = computed(() => {
    const rooms = this.rooms();
    const currentFilter = this.filter();

    if (currentFilter === 'all') return rooms;
    if (currentFilter === 'dirty') return rooms.filter(r => r.cleaning_status === 'dirty');
    return rooms.filter(r => r.status === currentFilter);
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
          this.rooms.set(res.data || []);
          this.loading.set(false); // Terminamos carga
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
      action: 'update',
      id: id,
      data: { cleaning_status: status }
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