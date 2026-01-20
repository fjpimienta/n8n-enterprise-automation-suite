import { Injectable, inject, signal } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Company, Guest, Room, User } from '@core/models/hotel.types';
import { environment } from '@env/environment';
import { lastValueFrom } from 'rxjs';
import { BookingService } from '@features/booking/services/booking.service';
import { AdminService } from '@features/admin/services/admin.service';

@Injectable({ providedIn: 'root' })
export class HotelService {
  private http = inject(HttpClient);
  private apiUrl_crud = environment.apiUrl_crud;
  public adminService = inject(AdminService);
  public bookingService = inject(BookingService);

  selectedRoom = signal<Room | null>(null); // Habitación para el detalle
  selectedCompany = signal<Company | null>(null); // Empresa para el detalle
  selectedUser = signal<User | null>(null); // Usuario para el detalle
  selectedGuest = signal<Guest | null>(null); // Usuario para el detalle

  /* Obtener todas las habitaciones */
  updateRoomStatus(id: number, status: string) {
    const payloadRoom = {
      entity: 'hotel_rooms',
      table_name: 'hotel_rooms',
      action: 'update',
      id: id,
      fields: { cleaning_status: status }
    };
    return this.http.post(`${this.apiUrl_crud}/${payloadRoom.table_name}`, payloadRoom, {
      headers: this.adminService.getAuthHeaders()
    });
  }

  /** Selecciona una habitación para ver su detalle */
  selectRoom(room: Room) {
    this.selectedRoom.set(room);
  }

  /** Limpia la selección de habitación */
  clearSelection() {
    this.selectedRoom.set(null);
  }

  /** Selecciona un usuario para editarlo */
  selectUser(user: User | null) {
    this.selectedUser.set(user);
  }
  
  /** Selecciona un huésped para editarlo */
  selectGuest(guest: Guest | null) {
    this.selectedGuest.set(guest);
  }

  /** Selecciona una empresa para ver su detalle */
  async updateRoomMaintenance(roomId: number): Promise<any> {
    return lastValueFrom( // Convertimos a promesa para usar tu async/await
      this.http.post(`${this.apiUrl_crud}/hotel_rooms`, {
        operation: 'update',
        id: roomId,
        fields: {
          status: 'maintenance',
          cleaning_status: 'dirty'
        }
      }, { headers: this.adminService.getAuthHeaders() })
    );
  }

  /** Finaliza el mantenimiento de una habitación */
  async finishMaintenance(roomId: number): Promise<any> {
    return lastValueFrom(
      this.http.post(`${this.apiUrl_crud}/hotel_rooms`, {
        operation: 'update',
        id: roomId,
        fields: {
          status: 'available',
          cleaning_status: 'dirty' // Pasa a limpieza antes de estar disponible
        }
      }, { headers: this.adminService.getAuthHeaders() })
    );
  }

}