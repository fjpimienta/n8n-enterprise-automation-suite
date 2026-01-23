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
  public filter = signal<'all' | 'available' | 'occupied' | 'dirty' | 'maintenance' | 'reserved'>('all');
  readonly translations: Record<'all' | 'available' | 'occupied' | 'dirty' | 'maintenance' | 'reserved', string> = {
    all: 'ninguno',  // O 'todos' si prefieres, pero "en estado: ninguno" tiene más sentido si no hay habitaciones en general
    available: 'disponible',
    occupied: 'ocupada',
    dirty: 'por limpiar',
    maintenance: 'mantenimiento',
    reserved: 'reservada'
  };
  translatedFilter = computed(() => this.translations[this.filter()]);

  /** Computed que filtra las habitaciones según el filtro seleccionado */
  public filteredRooms = computed(() => {
    const rooms = this.roomsWithStatus();
    const currentFilter = this.filter();

    switch (currentFilter) {
      case 'available':
        // Físicamente disponibles, limpias Y que NO tengan entrada hoy
        return rooms.filter(r =>
          r.status === 'available' &&
          (r.cleaning_status === 'clean' || r.cleaning_status === 'inspected') &&
          !r.hasIncomingToday
        );

      case 'reserved':
        // Habitaciones que tienen una reserva confirmada para entrar HOY
        return rooms.filter(r => r.hasIncomingToday && r.status === 'available');

      case 'occupied':
        // SOLO las que están físicamente ocupadas (Status 'occupied' en DB)
        return rooms.filter(r => r.status === 'occupied');

      case 'dirty':
        // Habitaciones que deben quedar libres hoy o están sucias
        return rooms.filter(r => r.cleaning_status === 'dirty');

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

      // Buscamos si hay una reserva que inicia hoy
      const hasIncomingToday = allReservations.some(res =>
        Number(res.room_id) === Number(room.id) &&
        res.status === 'confirmed' &&
        res.check_in.split(/[ T]/)[0] === todayStr
      );

      return {
        ...room,
        status: room.status,
        displayDate: room.status === 'occupied' ? currentCheckOut : nextCheckIn,
        isCheckoutDate: room.status === 'occupied' && currentCheckOut === todayStr,
        hasIncomingReservation: nextCheckIn !== null,
        hasIncomingToday
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
      fields: { room_id: roomId }
    };

    const res = await lastValueFrom(
      this.http.post<ApiResponse<any>>(`${this.apiUrl_crud}/hotel_bookings`, payload, {
        headers: this.adminService.getAuthHeaders()
      })
    );

    if (res.data && res.data.length > 0) {
      // 1. Intentamos buscar la reserva que está actualmente en curso (checked_in)
      const currentStay = res.data.find((b: any) =>
        b.status === 'checked_in' || b.status === 'confirmed' &&
        b.id
      );

      // 2. Si no hay una explícita, buscamos por fecha
      const actualStay = res.data.find((b: any) => {
        if (!b.check_in || !b.check_out) return false;
        const checkIn = b.check_in.split(/[ T]/)[0];
        const checkOut = b.check_out.split(/[ T]/)[0];
        return todayStr >= checkIn && todayStr < checkOut;
      });

      const result = currentStay || actualStay || res.data[0];

      // VALIDACIÓN: Si el objeto encontrado está vacío (como en tu log), devolvemos null
      return (result && result.id) ? result : null;
    }

    return null;
  }

  /** Procesa el check-in: puede ser walk-in o reserva previa */
  public async processCheckin(formData: any, room: Room, existingBookingId?: number): Promise<void> {
    const crudUrl = this.apiUrl_crud;
    this.isProcessing.set(true);

    try {
      // --- ESCENARIO A: TRANSICIÓN DE RESERVA (El cliente ya reservó) ---
      if (existingBookingId) {
        // console.log(`🔄 Procesando Check-in de Reserva existente: ${existingBookingId}`);

        // 1. Actualizamos la reserva existente para marcarla como ACTIVA
        // Cambiamos status a 'checked_in' (o 'confirmed' según tu lógica de negocio)
        // y actualizamos la hora real de llegada.
        await lastValueFrom(
          this.http.post(`${crudUrl}/hotel_bookings`, {
            operation: 'update',
            id: existingBookingId,
            fields: {
              status: 'checked_in', // Importante para diferenciar de una reserva futura
              check_in: new Date().toISOString(), // Hora real de entrada
              // Opcional: Si quieres actualizar notas o pagar algo al llegar
              payment_status: formData.payment_status || 'pending'
            }
          }, { headers: this.adminService.getAuthHeaders() })
        );

      }
      // --- ESCENARIO B: WALK-IN (Cliente nuevo llegando en el momento) ---
      else {
        // 1. Insertar o Buscar Huésped
        // Si el formData trae un ID de cliente ya seleccionado, úsalo. Si no, crea uno.
        let guestId = formData.guest_id;

        if (!guestId) {
          const guestRes: any = await lastValueFrom(
            this.http.post(`${crudUrl}/hotel_guests`, {
              operation: 'insert',
              fields: {
                full_name: formData.full_name,
                phone: formData.phone,
                doc_id: formData.doc_id,
                id_company: 1,
                email: formData.email || null,
                country: formData.country || 'México',
                state: formData.state || '',
                city: formData.city || '',
                notes: formData.notes || '',
                vip_status: formData.vip_status || false,
                requires_invoice: formData.requires_invoice || false
              }
            }, { headers: this.adminService.getAuthHeaders() })
          );
          guestId = guestRes?.data?.[0]?.id || guestRes?.id || guestRes?.data?.id;
        }

        if (!guestId) throw new Error("No se pudo obtener el ID del huésped");

        // 2. Crear la Nueva Reserva
        await lastValueFrom(
          this.http.post(`${crudUrl}/hotel_bookings`, {
            operation: 'insert',
            fields: {
              room_id: room.id,
              guest_id: guestId,
              check_in: new Date().toISOString(), // Ahora mismo
              check_out: formData.check_out,
              total_amount: formData.total_amount || 0,
              status: 'checked_in', // Nace directamente en check-in
              payment_status: 'pending',
              id_company: 1
            }
          }, { headers: this.adminService.getAuthHeaders() })
        );
      }

      // --- PASO COMÚN FINAL: OCUPAR LA HABITACIÓN FÍSICAMENTE ---
      // Esto es lo que "cierra" la disponibilidad en el calendario visual
      await lastValueFrom(
        this.http.post(`${crudUrl}/hotel_rooms`, {
          operation: 'update',
          id: room.id,
          fields: {
            status: 'occupied',       // La habitación pasa a Ocupada
            cleaning_status: 'clean'  // Asumimos que entra limpia
          }
        }, { headers: this.adminService.getAuthHeaders() })
      );

      // Recargar habitaciones para actualizar la vista
      this.loadRooms();

    } catch (error) {
      console.error('❌ Error en Check-in:', error);
      throw error;
    } finally {
      this.isProcessing.set(false);
    }
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

  /** Actualiza el estado de limpieza de una habitación */
  public async updateCleaningStatus(roomId: number, status: 'dirty' | 'clean' | 'inspected'): Promise<void> {
    const crudUrl = environment.apiUrl_crud;

    await lastValueFrom(
      this.http.post(`${crudUrl}/hotel_rooms`, {
        operation: 'update',
        id: roomId,
        fields: {
          cleaning_status: status
        }
      }, { headers: this.adminService.getAuthHeaders() })
    );

    // Recargamos para que los filtros del dashboard se actualicen
    this.loadRooms();
  }

  /** 1. VERIFICAR DISPONIBILIDAD DE HABITACIONES */
  public async checkAvailability(
    checkIn: string,
    checkOut: string,
    allRooms: Room[],
    excludeId?: number
  ): Promise<Room[]> {
    this.reportService.loadingReports.set(true);

    try {
      const payload = {
        operation: 'getall',
        table_name: 'hotel_bookings',
        fields: { status: 'confirmed' }
      };

      const res: any = await lastValueFrom(
        this.http.post<ApiResponse<any>>(`${this.apiUrl_crud}/hotel_bookings`, payload, {
          headers: this.adminService.getAuthHeaders()
        })
      );

      const bookings = res.data || [];

      // Normalización: Comparamos solo fechas (00:00:00) para evitar conflictos por horas
      const start = new Date(checkIn).setHours(0, 0, 0, 0);
      const end = new Date(checkOut).setHours(0, 0, 0, 0);

      const occupiedRoomIds = bookings
        .filter((b: any) => {
          // 1. Si estamos editando, omitimos la reserva actual del cálculo de colisiones
          if (excludeId && Number(b.id) === Number(excludeId)) {
            return false;
          }

          // 2. Normalizar fechas de la reserva existente
          const bStart = new Date(b.check_in).setHours(0, 0, 0, 0);
          const bEnd = new Date(b.check_out).setHours(0, 0, 0, 0);

          // 3. Lógica de solapamiento estándar (Industry Standard)
          // Permite que un Huésped B entre el mismo día que el Huésped A sale.
          return (start < bEnd && end > bStart);
        })
        .map((b: any) => b.room_id);

      // Retornar habitaciones que NO tienen colisiones
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
      console.log('formData: ', formData);
      let finalDocId = formData.doc_id;
      if (!finalDocId || finalDocId.trim() === '') {
        finalDocId = this.adminService.generateInternalId();
      }
      let finalEmail = formData.email;
      if (!finalEmail || finalEmail.trim() === '') {
        finalEmail = this.adminService.generateDummyEmail();
      }
      const guestRes: any = await lastValueFrom(
        this.http.post(`${this.apiUrl_crud}/hotel_guests`, {
          operation: 'insert',
          fields: {
            full_name: formData.full_name,
            phone: formData.phone,
            email: finalEmail, // Opcional si es reserva telefónica
            doc_id: finalDocId, // Opcional si es reserva telefónica
            notes: formData.notes,
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
            notes: 'Reserva Futura',
            id_company: 1
          }
        }, { headers: this.adminService.getAuthHeaders() })
      );

      // ¡OJO! Aquí NO llamamos a updateRoomStatus. La habitación sigue disponible HOY.

    } finally {
      this.isProcessing.set(false);
    }
  }

  /** Actualizar la reserva */
  public async updateReservation(formData: any): Promise<void> {
    this.isProcessing.set(true);
    try {
      await lastValueFrom(
        this.http.post(`${this.apiUrl_crud}/hotel_bookings`, {
          operation: 'update',
          fields: {
            id: formData.id,
            room_id: formData.room_id,
            check_in: formData.check_in,
            check_out: formData.check_out,
            total_amount: Number(formData.total_amount),
            notes: formData.notes, // Incluimos las notas por si cambiaron
            id_company: 1
          }
        }, { headers: this.adminService.getAuthHeaders() })
      );
    } catch (error) {
      console.error("Error al actualizar reserva:", error);
      throw error;
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