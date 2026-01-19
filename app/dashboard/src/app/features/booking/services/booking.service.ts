import { Injectable, computed, inject, signal } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { lastValueFrom } from 'rxjs';
import { ApiResponse } from '@core/interfaces/api-response.interface';
import { AdminService } from '@features/admin/services/admin.service';
import { ReportService } from '@features/finance/services/report.service';
import { environment } from '@env/environment';
import { Room } from '@core/models/hotel.types';

@Injectable({ providedIn: 'root' })
export class BookingService {
  private http = inject(HttpClient);
  private apiUrl_crud = environment.apiUrl_crud;
  public adminService = inject(AdminService);
  public reportService = inject(ReportService);
  public loadingRooms = signal<boolean>(false);
  public rooms = signal<Room[]>([]);
  public isProcessing = signal<boolean>(false);
  public filter = signal<'all' | 'available' | 'occupied' | 'dirty' | 'maintenance'>('available');

  /** Computed que filtra las habitaciones según el filtro seleccionado */
  public filteredRooms = computed(() => {
    const rooms = this.rooms();
    const currentFilter = this.filter();

    switch (currentFilter) {
      case 'available':
        // Solo disponibles y limpias, SIN reservas para hoy
        return rooms.filter(r =>
          r.status === 'available' &&
          (r.cleaning_status === 'clean' || r.cleaning_status === 'inspected') 
        );

      case 'occupied':
        // SOLO las que están físicamente ocupadas (Status 'occupied' en DB)
        return rooms.filter(r => r.status === 'occupied');

      case 'dirty':
        // Habitaciones que deben quedar libres hoy o están sucias
        return rooms.filter(r =>
          (r.status === 'available' && r.cleaning_status === 'dirty') ||
          (r.status === 'occupied')
        );

      case 'maintenance':
        return rooms.filter(r => r.status === 'maintenance');

      default: // 'all'
        return rooms;
    }
  });

  /** Computed que añade estado 'reserved' a habitaciones con reserva activa HOY */
  public roomsWithStatus = computed(() => {
    const allRooms = this.rooms();
    const allReservations = this.adminService.reservations();
    const now = new Date();
    // Forzamos formato YYYY-MM-DD local para evitar desfases de zona horaria
    const todayStr = now.toLocaleDateString('sv-SE');

    return allRooms.map(room => {
      // 1. Ocupación actual (Huésped que está físicamente ahí hoy)
      const currentStay = allReservations.find(res =>
        Number(res.room_id) === Number(room.id) &&
        res.status?.toLowerCase().trim() === 'confirmed' &&
        res.check_in.split(/[ T]/)[0] <= todayStr &&
        res.check_out.split(/[ T]/)[0] > todayStr
      );

      // 2. PRÓXIMAS reservas (Cualquiera que entre hoy mismo o después)
      const futureReservations = allReservations
        .filter(res =>
          Number(res.room_id) === Number(room.id) &&
          ['confirmed', 'pending'].includes(res.status?.toLowerCase().trim()) &&
          res.check_in.split(/[ T]/)[0] >= todayStr &&
          res.id !== currentStay?.id // No es la que ya está ocupando la habitación
        )
        .sort((a, b) => a.check_in.localeCompare(b.check_in));

      const nextRes = futureReservations[0];
      const nextCheckIn = nextRes ? nextRes.check_in.split(/[ T]/)[0] : null;

      // USAMOS currentStay para la fecha de salida si está ocupada
      const currentCheckOut = currentStay ? currentStay.check_out.split(/[ T]/)[0] : null;

      return {
        ...room,
        status: room.status,
        displayDate: room.status === 'occupied' ? currentCheckOut : nextCheckIn,
        isCheckoutDate: room.status === 'occupied' && currentCheckOut === todayStr,
        hasIncomingReservation: nextCheckIn !== null,
        hasIncomingToday: nextCheckIn === todayStr
      };
    });
  });

  /** Carga todas las habitaciones del hotel */
  public loadRooms() {
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
      headers: this.adminService.getAuthHeaders()
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

  /** Obtener la reserva activa (la que está ocupando la habitación AHORA) */
  public async getActiveBooking(roomId: number): Promise<any> {
    const todayStr = new Date().toLocaleDateString('sv-SE'); // YYYY-MM-DD

    const payload = {
      operation: 'getall',
      // Filtramos por habitación y status confirmado
      fields: { room_id: roomId, status: 'confirmed' }
    };

    const res = await lastValueFrom(
      this.http.post<ApiResponse<any>>(`${this.apiUrl_crud}/hotel_bookings`, payload, {
        headers: this.adminService.getAuthHeaders()
      })
    );

    if (res.data && res.data.length > 0) {
      // IMPORTANTE: Buscamos la reserva donde HOY esté entre check_in y check_out
      const actualStay = res.data.find((b: any) => {
        const checkIn = b.check_in.split(/[ T]/)[0];
        const checkOut = b.check_out.split(/[ T]/)[0];
        return todayStr >= checkIn && todayStr < checkOut;
      });

      // Si no encuentra una por fecha (ej. el check-in es tarde), devolvemos la más antigua confirmed
      return actualStay || res.data[0];
    }

    return null;
  }

  /** Incluye creación de huésped, reserva y actualización de estado de habitación */
  public async processCheckin(formData: any, room: Room): Promise<void> {
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
      }, { headers: this.adminService.getAuthHeaders() })
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
      }, { headers: this.adminService.getAuthHeaders() })
    );

    // 3. Cambiar estado de la Habitación a Ocupada
    await lastValueFrom(
      this.http.post(`${crudUrl}/hotel_rooms`, {
        operation: 'update',
        id: room.id,
        fields: {
          status: 'occupied',
          cleaning_status: 'clean'
        }
      }, { headers: this.adminService.getAuthHeaders() })
    );
  }

  /** Procesa el dirty: actualiza reserva y libera habitación */
  public async processCheckout(room: Room, bookingId: number, inventoryReport: string, checks: any): Promise<void> {
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
      }, { headers: this.adminService.getAuthHeaders() })
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
      }, { headers: this.adminService.getAuthHeaders() })
    );

    this.loadRooms();
  }

  /** 1. VERIFICAR DISPONIBILIDAD DE HABITACIONES */
  public async checkAvailability(checkIn: string, checkOut: string, allRooms: Room[]): Promise<Room[]> {
    this.reportService.loadingReports.set(true); // Reusamos el loading o creamos uno nuevo

    try {
      // Pedimos todas las reservas que estén confirmadas (status 'confirmed')
      // Nota: Idealmente filtraríamos por fecha en n8n, pero traer todo y filtrar aquí es seguro para 17 habs.
      const payload = {
        operation: 'getall',
        table_name: 'hotel_bookings',
        fields: { status: 'confirmed' } // Solo las activas
      };

      const res: any = await lastValueFrom(
        this.http.post<ApiResponse<any>>(`${this.apiUrl_crud}/hotel_bookings`, payload, {
          headers: this.adminService.getAuthHeaders()
        })
      );

      const bookings = res.data || [];
      const start = new Date(checkIn).getTime();
      const end = new Date(checkOut).getTime();

      // Encontramos las habitaciones ocupadas en ese rango
      const occupiedRoomIds = bookings
        .filter((b: any) => {
          const bStart = new Date(b.check_in).getTime();
          const bEnd = new Date(b.check_out).getTime();
          // Lógica de solapamiento de fechas
          return (start < bEnd && end > bStart);
        })
        .map((b: any) => b.room_id);

      // Devolvemos las habitaciones que NO estén en la lista de ocupadas
      return allRooms.filter(room => !occupiedRoomIds.includes(room.id));

    } finally {
      this.reportService.loadingReports.set(false);
    }
  }

  /** 2. CREAR RESERVA FUTURA */
  public async createFutureReservation(formData: any, roomId: number): Promise<void> {
    this.isProcessing.set(true);
    try {
      // A. Insertar o Buscar Huésped (Reutilizamos lógica o creamos nuevo)
      const guestRes: any = await lastValueFrom(
        this.http.post(`${this.apiUrl_crud}/hotel_guests`, {
          operation: 'insert',
          fields: {
            full_name: formData.full_name,
            phone: formData.phone,
            doc_id: formData.doc_id, // Opcional si es reserva telefónica
            id_company: 1
          }
        }, { headers: this.adminService.getAuthHeaders() })
      );

      const guestId = guestRes?.data?.[0]?.id || guestRes?.id;

      // B. Insertar la Reserva
      await lastValueFrom(
        this.http.post(`${this.apiUrl_crud}/hotel_bookings`, {
          operation: 'insert',
          fields: {
            room_id: roomId,
            guest_id: guestId,
            check_in: formData.check_in,
            check_out: formData.check_out,
            total_amount: formData.total_amount || 0,
            status: 'confirmed',     // Confirmada
            payment_status: 'pending', // Generalmente se paga al llegar o anticipo
            notes: 'Reserva Futura'
          }
        }, { headers: this.adminService.getAuthHeaders() })
      );

      // ¡OJO! Aquí NO llamamos a updateRoomStatus. La habitación sigue disponible HOY.

    } finally {
      this.isProcessing.set(false);
    }
  }

  /** Registrar pago de una reserva */
  public async registerPayment(bookingId: number): Promise<void> {
    await lastValueFrom(
      this.http.post(`${this.apiUrl_crud}/hotel_bookings`, {
        operation: 'update',
        id: bookingId,
        fields: { payment_status: 'paid' }
      }, { headers: this.adminService.getAuthHeaders() })
    );
  }
}