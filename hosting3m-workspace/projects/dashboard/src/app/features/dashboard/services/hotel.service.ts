import { Injectable, inject, signal } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Company, Guest, Room, User } from '@core/models/hotel.types';
import { environment } from '@env/environment';
import { lastValueFrom, map, Observable, shareReplay } from 'rxjs';
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
          cleaning_status: 'clean'
        }
      }, { headers: this.adminService.getAuthHeaders() })
    );
  }

  /** Caché en vuelo por (roomId, date) para evitar peticiones duplicadas */
  private checklistCache = new Map<string, Observable<any | null>>();

  /**
   * Obtiene el checklist de hoy para una habitación. Usa caché para evitar peticiones duplicadas.
   */
  getTodayChecklist(roomId: number): Observable<any | null> {
    const today = new Date().toISOString().split('T')[0];
    const key = `${roomId}-${today}`;

    if (!this.checklistCache.has(key)) {
      const payload = {
        entity: "hotel_room_inspections",
        table_name: "hotel_room_inspections",
        operation: "getall",
        action: "list",
        filters: { room_id: roomId, inspection_date: today }
      };

      const req$ = this.http.post<any>(`${this.apiUrl_crud}/hotel_room_inspections`, payload).pipe(
        map((response: any) => {
          const data = response.data || response;
          return Array.isArray(data) && data.length > 0 ? data[0] : null;
        }),
        shareReplay({ bufferSize: 1, refCount: true })
      );
      this.checklistCache.set(key, req$);
    }
    return this.checklistCache.get(key)!;
  }

  /** Invalida caché de checklist tras save/update para que el próximo getTodayChecklist traiga datos frescos */
  invalidateChecklistCache(roomId?: number): void {
    if (roomId) {
      const today = new Date().toISOString().split('T')[0];
      this.checklistCache.delete(`${roomId}-${today}`);
    } else {
      this.checklistCache.clear();
    }
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
      operation: "update",
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