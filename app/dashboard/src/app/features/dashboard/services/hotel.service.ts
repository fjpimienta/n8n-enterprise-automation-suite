import { Injectable, inject, signal } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Company, Room, User } from '@core/models/hotel.types';
import { environment } from '@env/environment';
import { lastValueFrom } from 'rxjs';
import { BookingService } from '@features/booking/services/booking.service';

@Injectable({ providedIn: 'root' })
export class HotelService {
  private http = inject(HttpClient);
  private apiUrl_crud = environment.apiUrl_crud;
  public loadingReports = signal<boolean>(false);
  public loadingCompanies = signal<boolean>(false);
  public bookingService = inject(BookingService);


  // Signal para estado reactivo (Best Practice Angular 19+)
  selectedRoom = signal<Room | null>(null); // Habitación para el detalle
  selectedCompany = signal<Company | null>(null); // Empresa para el detalle
  selectedUser = signal<User | null>(null); // Usuario para el detalle

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
      headers: this.bookingService.getAuthHeaders()
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

  /** Selecciona un usuario para editarlo */
  selectUser(user: User | null) {
    this.selectedUser.set(user);
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
        }, { headers: this.bookingService.getAuthHeaders() })
      );
      return Array.isArray(res?.data) ? res.data : [];
    } finally {
      this.loadingReports.set(false);
    }
  }

  async updateRoomMaintenance(roomId: number): Promise<any> {
    return lastValueFrom( // Convertimos a promesa para usar tu async/await
      this.http.post(`${this.apiUrl_crud}/hotel_rooms`, {
        operation: 'update',
        id: roomId,
        fields: {
          status: 'maintenance',
          cleaning_status: 'dirty'
        }
      }, { headers: this.bookingService.getAuthHeaders() })
    );
  }

  async finishMaintenance(roomId: number): Promise<any> {
    return lastValueFrom(
      this.http.post(`${this.apiUrl_crud}/hotel_rooms`, {
        operation: 'update',
        id: roomId,
        fields: {
          status: 'available',
          cleaning_status: 'dirty' // Pasa a limpieza antes de estar disponible
        }
      }, { headers: this.bookingService.getAuthHeaders() })
    );
  }

}