import { Injectable, inject, signal } from '@angular/core';
import { HttpClient, HttpHeaders } from '@angular/common/http';
import { Room } from '../models/hotel.types';
import { environment } from '../../environments/environment';

@Injectable({ providedIn: 'root' })
export class HotelService {
  private http = inject(HttpClient);
  private apiUrl_crud = environment.apiUrl_crud; // Tu URL de n8n

  // Signal para estado reactivo (Best Practice Angular 19+)
  rooms = signal<Room[]>([]);

  // Función auxiliar para obtener los headers con el authToken
  private getAuthHeaders() {
    const authToken = localStorage.getItem('authToken'); // O de donde guardes tu JWT
    return new HttpHeaders({
      'Authorization': `Bearer ${authToken}`
    });
  }

  loadRooms() {
    const payload = {
      entity: 'hotel_rooms',
      action: 'list',
      filters: {}
    };

    this.http.post<any>(`${this.apiUrl_crud}/${payload.entity}`, payload, {
      headers: this.getAuthHeaders()
    })
      .subscribe({
        next: (response) => {
          // Accedemos específicamente a la propiedad 'data' que vimos en el log
          if (response && response.data) {
            this.rooms.set(response.data);
          } else {
            console.warn('La respuesta no contiene la propiedad data:', response);
            this.rooms.set([]); // Limpiamos para evitar errores
          }
        },
        error: (e) => {
          console.error('Error cargando habitaciones', e);
          this.rooms.set([]); // Limpiamos en caso de error de red
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
}