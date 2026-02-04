import { Injectable, inject, signal } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Company, Guest, Room, User } from '@core/models/hotel.types';
import { environment } from '@env/environment';
import { lastValueFrom, map, Observable } from 'rxjs';
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

  /**
   * ✅ CORREGIDO: Usamos POST con el formato que tu n8n espera (CRUD V3)
   */
  getTodayChecklist(roomId: number): Observable<any | null> {
    const today = new Date().toISOString().split('T')[0];

    // Estructura idéntica a la que usas para 'hotel_bookings'
    const payload = {
      entity: "hotel_room_inspections",
      table_name: "hotel_room_inspections",
      operation: "getall", // Usamos getall + filtros para buscar
      action: "list",
      filters: {
        room_id: roomId,
        inspection_date: today
      }
    };

    // Apuntamos al webhook base pasando el modelo en la URL si es necesario, 
    // o simplemente al endpoint principal.
    // Basado en tu URL: .../crud/v3/:model
    return this.http.post<any>(`${this.apiUrl_crud}/hotel_room_inspections`, payload).pipe(
      map((response: any) => {
        const data = response.data || response;

        if (Array.isArray(data) && data.length > 0) {
          return data[0];
        }
        return null;
      })
    );
  }

  /**
   * ✅ Guardar Rondín (Create)
   */
  saveChecklist(roomId: number, checklist: any, observaciones: string): Observable<any> {
    const payload = {
      entity: "hotel_room_inspections",
      table_name: "hotel_room_inspections",
      operation: "insert", // Mantenemos "insert" para que entre en el case correcto
      action: "insert",

      // ✅ CORRECCIÓN: Cambiamos 'data' por 'fields'
      // Así el script de n8n sabrá exactamente qué insertar.
      fields: {
        room_id: roomId,
        checklist_data: checklist,
        observaciones: observaciones || "",
        inspection_date: new Date().toISOString().split('T')[0],
        id_company: 1
      }
    };

    return this.http.post(`${this.apiUrl_crud}/hotel_room_inspections`, payload);
  }

  /**
   * Actualiza un rondín existente (UPDATE)
   */
  updateChecklist(inspectionId: number, checklist: any, observaciones: string): Observable<any> {
    const payload = {
      entity: "hotel_room_inspections",
      table_name: "hotel_room_inspections",
      operation: "update", // 👈 La clave es cambiar a 'update'
      action: "update",

      fields: {
        id: inspectionId,
        checklist_data: checklist,
        observaciones: observaciones || ""
      }
    };

    return this.http.post(`${this.apiUrl_crud}/hotel_room_inspections`, payload);
  }

}