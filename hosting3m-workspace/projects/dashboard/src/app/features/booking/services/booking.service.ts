import { Injectable, computed, inject, signal } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { lastValueFrom } from 'rxjs';
import { ApiResponse } from '@core/interfaces/api-response.interface';
import { AdminService } from '@features/admin/services/admin.service';
import { ReportService } from '@features/finance/services/report.service';
import { environment } from '@env/environment';
import { Room, RoomGroup } from '@core/models/hotel.types';

@Injectable({ providedIn: 'root' })
export class BookingService {
  private http = inject(HttpClient);
  private apiUrl_crud = environment.apiUrl_crud;
  public adminService = inject(AdminService);
  public reportService = inject(ReportService);
  public loadingRooms = signal<boolean>(false);
  public rooms = signal<Room[]>([]);
  public roomGroup = signal<RoomGroup[]>([]);
  public isProcessing = signal<boolean>(false);
  public searchQuery = signal<string>('');
  public filter = signal<'all' | 'available' | 'occupied' | 'dirty' | 'maintenance' | 'reserved' | 'checkout_today'>('available');
  public translatedFilter = computed(() => this.translations[this.filter()]);

  readonly translations: Record<'all' | 'available' | 'occupied' | 'dirty' | 'maintenance' | 'reserved' | 'checkout_today', string> = {
    all: 'ninguno',
    available: 'disponible',
    occupied: 'ocupada',
    dirty: 'por limpiar',
    maintenance: 'mantenimiento',
    reserved: 'reservada',
    checkout_today: 'salidas hoy'
  };

  private readonly roomTypeConfig = [
    { key: 'SENCILLA', label: '💑 Sencilla', order: 1 },
    { key: 'KING', label: '👑 King Size', order: 2 },
    { key: 'DOBLE', label: '👯 Doble', order: 3 },
    { key: 'TRIPLE', label: '👨‍👩‍👧 Triple', order: 4 },
    { key: 'INDIVIDUAL', label: '👤 Individual', order: 5 }
  ];

  public filteredRooms = computed(() => {
    let rooms = this.roomsWithStatus();
    const query = this.searchQuery().trim().toLowerCase();
    if (query.length > 0) {
      rooms = rooms.filter(r => r.room_number.toLowerCase().includes(query));
    }
    const currentFilter = this.filter();

    switch (currentFilter) {
      case 'available':
        return rooms.filter(r =>
          r.status === 'available' &&
          (r.cleaning_status === 'clean' || r.cleaning_status === 'inspected') &&
          !r.hasIncomingToday
        );
      case 'reserved':
        return rooms.filter(r => r.hasIncomingToday && r.status === 'available');
      case 'checkout_today':
        return rooms.filter(r => r.isCheckoutDate === true && r.status === 'occupied');
      case 'occupied':
        return rooms.filter(r => r.status === 'occupied');
      case 'dirty':
        return rooms.filter(r => r.cleaning_status === 'dirty');
      case 'maintenance':
        return rooms.filter((r: any) => r.status === 'maintenance' || r.hasPendingTicket);
      default:
        return rooms;
    }
  });

  public groupedRooms = computed(() => {
    const currentRooms = this.filteredRooms();
    const groupsMap = new Map<string, Room[]>();

    currentRooms.forEach(room => {
      let typeKey = (room.type || 'OTHER').toUpperCase().trim();

      if (typeKey.includes('KING')) typeKey = 'KING';
      else if (typeKey.includes('SENCILLA')) typeKey = 'SENCILLA';
      else if (typeKey.includes('DOBLE')) typeKey = 'DOBLE';
      else if (typeKey.includes('TRIPLE')) typeKey = 'TRIPLE';

      if (!groupsMap.has(typeKey)) {
        groupsMap.set(typeKey, []);
      }
      groupsMap.get(typeKey)!.push(room);
    });

    const resultGroups: RoomGroup[] = [];

    this.roomTypeConfig.forEach(config => {
      const rooms = groupsMap.get(config.key);
      if (rooms && rooms.length > 0) {
        rooms.sort((a, b) => a.room_number.localeCompare(b.room_number, undefined, { numeric: true }));
        resultGroups.push({
          key: config.key,
          label: config.label,
          order: config.order,
          rooms: rooms
        });
        groupsMap.delete(config.key);
      }
    });

    groupsMap.forEach((rooms, key) => {
      if (rooms.length > 0) {
        rooms.sort((a, b) => a.room_number.localeCompare(b.room_number, undefined, { numeric: true }));
        resultGroups.push({
          key: key,
          label: `🛏️ ${key}`,
          order: 99,
          rooms: rooms
        });
      }
    });

    return resultGroups;
  });

  public roomsWithStatus = computed(() => {
    const allRooms = this.rooms();
    const allReservations = this.adminService.reservations();

    // 🚨 FECHA MANUAL BLINDADA PARA LINUX/UBUNTU
    const now = new Date();
    const year = now.getFullYear();
    const month = String(now.getMonth() + 1).padStart(2, '0');
    const day = String(now.getDate()).padStart(2, '0');
    const todayStr = `${year}-${month}-${day}`;

    return allRooms.map(room => {
      const currentStay = allReservations.find(res =>
        Number(res.room_id) === Number(room.id) &&
        res.status?.toLowerCase().trim() === 'checked_in'
      ) || allReservations.find(res =>
        Number(res.room_id) === Number(room.id) &&
        ['confirmed', 'pending'].includes(res.status?.toLowerCase().trim()) &&
        res.check_in.split(/[ T]/)[0] <= todayStr &&
        res.check_out.split(/[ T]/)[0] > todayStr
      );

      const futureReservations = allReservations
        .filter(res =>
          Number(res.room_id) === Number(room.id) &&
          ['confirmed', 'pending'].includes(res.status?.toLowerCase().trim()) &&
          res.check_in.split(/[ T]/)[0] >= todayStr &&
          res.id !== currentStay?.id
        )
        .sort((a, b) => a.check_in.localeCompare(b.check_in));

      const nextRes = futureReservations[0];
      const nextCheckIn = nextRes ? nextRes.check_in.split(/[ T]/)[0] : null;
      const currentCheckOut = currentStay ? currentStay.check_out.split(/[ T]/)[0] : null;

      const hasIncomingToday = allReservations.some(res =>
        Number(res.room_id) === Number(room.id) &&
        ['confirmed', 'pending'].includes(res.status?.toLowerCase().trim()) &&
        res.check_in.split(/[ T]/)[0] === todayStr
      );

      return {
        ...room,
        status: room.status,
        displayDate: room.status === 'occupied' ? currentCheckOut : nextCheckIn,
        isCheckoutDate: room.status === 'occupied' && currentCheckOut === todayStr,
        hasIncomingReservation: nextCheckIn !== null,
        hasIncomingToday,
        hasPendingTicket: (room as any).hasPendingTicket
      };
    });
  });

  public loadRooms() {
    this.loadingRooms.set(true);
    const token = localStorage.getItem('authToken');
    if (!token) return;

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
        next: async (res) => { // Agregamos async aquí
          if (res && !res.error && res.data) {
            let data = Array.isArray(res.data) ? res.data : [];

            // 📡 RADAR DE TICKETS MASIVO: Buscamos todos los tickets pendientes
            try {
              const ticketsRes: any = await lastValueFrom(
                this.http.post(`${this.apiUrl_crud}/hotel_maintenance_tickets`, {
                  operation: 'getall',
                  fields: { status: 'PENDING' }
                }, { headers: this.adminService.getAuthHeaders() })
              );

              const pendingTickets = Array.isArray(ticketsRes.data) ? ticketsRes.data : [];

              // Le inyectamos la bandera "hasPendingTicket" a cada habitación
              data = data.map(room => {
                const roomHasTicket = pendingTickets.some((t: any) => t.room_id === room.id);
                return { ...room, hasPendingTicket: roomHasTicket };
              });
            } catch (error) {
              console.warn('No se pudo cargar el radar de tickets globales', error);
            }

            const sortedRooms = [...data].sort((a, b) =>
              String(a.room_number).localeCompare(String(b.room_number), undefined, { numeric: true })
            );
            this.rooms.set(sortedRooms);
          } else {
            this.rooms.set([]);
          }
          this.loadingRooms.set(false);
        },
        error: (err) => {
          this.rooms.set([]);
          this.loadingRooms.set(false);
        }
      });
  }

  public async getActiveBooking(roomId: number): Promise<any> {
    const now = new Date();
    const year = now.getFullYear();
    const month = String(now.getMonth() + 1).padStart(2, '0');
    const day = String(now.getDate()).padStart(2, '0');
    const todayStr = `${year}-${month}-${day}`;

    const payload = {
      operation: 'getall',
      fields: { room_id: roomId }
    };

    const res = await lastValueFrom(
      this.http.post<ApiResponse<any>>(`${this.apiUrl_crud}/hotel_bookings`, payload, {
        headers: this.adminService.getAuthHeaders()
      })
    );

    if (res.data && res.data.length > 0) {
      const currentStay = res.data.find((b: any) =>
        b.status === 'checked_in' || b.status === 'confirmed' && b.id
      );

      const actualStay = res.data.find((b: any) => {
        if (!b.check_in || !b.check_out) return false;
        const checkIn = b.check_in.split(/[ T]/)[0];
        const checkOut = b.check_out.split(/[ T]/)[0];
        return todayStr >= checkIn && todayStr < checkOut;
      });

      const result = currentStay || actualStay || res.data[0];
      return (result && result.id) ? result : null;
    }
    return null;
  }

  /** Busca una reserva activa o una confirmada/pendiente válida para hoy */
  public async findActiveOrTodayReservation(room: Room): Promise<any | null> {
    if (room.status === 'occupied') {
      return await this.getActiveBooking(room.id);
    }

    // 🚨 FECHA MANUAL BLINDADA PARA LINUX/UBUNTU
    const now = new Date();
    const year = now.getFullYear();
    const month = String(now.getMonth() + 1).padStart(2, '0');
    const day = String(now.getDate()).padStart(2, '0');
    const todayStr = `${year}-${month}-${day}`;

    const allReservations = this.adminService.reservations();

    // 🛠️ FIX: Filtramos estrictamente reservas que APLICAN PARA HOY
    const validReservations = allReservations.filter(r => {
      if (!r.check_in || !r.check_out) return false;

      const checkInStr = String(r.check_in).split(/[ T]/)[0];
      const checkOutStr = String(r.check_out).split(/[ T]/)[0];
      const status = String(r.status || '').toLowerCase().trim();

      return Number(r.room_id) === Number(room.id) &&
        ['confirmed', 'pending'].includes(status) &&
        checkInStr <= todayStr && // 🚀 PREVIENE EL BUG: Ignora reservas del futuro (deben empezar hoy o antes)
        checkOutStr > todayStr;   // Y obviamente no deben haber caducado
    }).sort((a, b) => String(a.check_in).localeCompare(String(b.check_in)));

    const reservation = validReservations[0];

    if (reservation) {
      const guestList = this.adminService.guests ? this.adminService.guests() : [];
      const guest = guestList.find(g => Number(g.id) === Number(reservation.guest_id));

      return {
        ...reservation,
        hotel_guests_data: guest || reservation.hotel_guests_data,
        guest_name: guest?.full_name || reservation.guest_name,
        guest_doc_id: guest?.doc_id || reservation.guest_doc_id,
        guest_phone: guest?.phone || reservation.guest_phone,
        guest_email: guest?.email || reservation.guest_email
      };
    }

    return null;
  }

  /** Procesa el check-in: puede ser walk-in o reserva previa */
  public async processCheckin(formData: any, room: Room, existingBookingId?: number): Promise<void> {
    const crudUrl = this.apiUrl_crud;
    this.isProcessing.set(true);

    try {
      const totalAmount = Number(formData.total_amount) || 0;
      const amountPaid = Number(formData.amount_paid) || 0;
      let paymentStatus = 'pending';

      if (amountPaid >= totalAmount && totalAmount > 0) paymentStatus = 'paid';
      else if (amountPaid > 0) paymentStatus = 'partial';

      // --- ESCENARIO A: TRANSICIÓN DE RESERVA ---
      if (existingBookingId) {
        const resUpd: any = await lastValueFrom(
          this.http.post(`${crudUrl}/hotel_bookings`, {
            operation: 'update',
            id: existingBookingId,
            fields: {
              status: 'checked_in',
              check_in: new Date().toISOString(),
              total_amount: totalAmount,
              amount_paid: amountPaid,
              payment_status: paymentStatus,
              is_invoiced: formData.is_invoiced || false
            }
          }, { headers: this.adminService.getAuthHeaders() })
        );
        // 🛑 ESCUDO ANTI-ERRORES SILENCIOSOS
        if (resUpd?.error) throw new Error(resUpd.message || 'Fallo DB: Update Reserva');

      }
      // --- ESCENARIO B: WALK-IN ---
      else {
        // 🚨 PREVENCIÓN DE OVERLAPPING: Validar que el walk-in no choque con reservas futuras confirmadas
        const isFree = await this.isRoomFree(room.id, new Date().toISOString(), formData.check_out);
        if (!isFree) {
          throw new Error(`La habitación ya tiene una reserva confirmada que choca con la fecha de salida seleccionada (${formData.check_out}). Por favor acorte la estancia o asigne otra habitación.`);
        }

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
          if (guestRes?.error) throw new Error(guestRes.message);
          guestId = guestRes?.data?.[0]?.id || guestRes?.id || guestRes?.data?.id;
        }

        if (!guestId) throw new Error("No se pudo obtener el ID del huésped");

        const insertRes: any = await lastValueFrom(
          this.http.post(`${crudUrl}/hotel_bookings`, {
            operation: 'insert',
            fields: {
              room_id: room.id,
              guest_id: guestId,
              check_in: new Date().toISOString(),
              check_out: formData.check_out,
              total_amount: totalAmount,
              amount_paid: amountPaid,
              status: 'checked_in',
              payment_status: paymentStatus,
              is_invoiced: formData.is_invoiced || false,
              id_company: 1
            }
          }, { headers: this.adminService.getAuthHeaders() })
        );
        if (insertRes?.error) throw new Error(insertRes.message || 'Fallo DB: Insertar Reserva');
      }

      // --- PASO COMÚN FINAL: OCUPAR LA HABITACIÓN ---
      const roomRes: any = await lastValueFrom(
        this.http.post(`${crudUrl}/hotel_rooms`, {
          operation: 'update',
          id: room.id,
          fields: {
            status: 'occupied',
            cleaning_status: 'clean'
          }
        }, { headers: this.adminService.getAuthHeaders() })
      );
      if (roomRes?.error) throw new Error(roomRes.message || 'Fallo DB: Ocupar Habitación');

      this.loadRooms();

    } catch (error) {
      console.error('❌ Error en Check-in:', error);
      throw error; // Propaga el error para que el Dashboard lance la alerta roja
    } finally {
      this.isProcessing.set(false);
    }
  }

  public async processCheckout(room: Room, bookingId: any, inventoryReport: string, checks: any): Promise<void> {
    const crudUrl = this.apiUrl_crud;

    // 🛠️ 1. SANITIZACIÓN DE ID: Por si el frontend envía el objeto completo por error
    const validId = typeof bookingId === 'object' ? bookingId.id : bookingId;

    if (!validId) {
      throw new Error("❌ No se detectó un ID de reserva válido para hacer el Check-out.");
    }

    // 🛠️ 2. SANITIZACIÓN DE INVENTARIO: Evitar valores undefined que rompan el JSON de n8n
    const safeChecks = checks || { tvRemote: true, acRemote: true, keys: true };

    // 3. ACTUALIZAR LA RESERVA A CHECKED_OUT
    const resOut: any = await lastValueFrom(
      this.http.post(`${crudUrl}/hotel_bookings`, {
        operation: 'update',
        id: validId,
        fields: {
          status: 'checked_out',
          check_out: new Date().toISOString(),
          notes: inventoryReport || '',
          inventory_tv_ok: safeChecks.tvRemote,
          inventory_ac_ok: safeChecks.acRemote,
          inventory_keys_ok: safeChecks.keys
        }
      }, { headers: this.adminService.getAuthHeaders() })
    );

    // 🛑 ESCUDO ANTI-ERRORES SILENCIOSOS (Detiene todo si PostgreSQL falla)
    if (resOut?.error) {
      throw new Error(`Fallo DB al cerrar reserva: ${resOut.message}`);
    }

    // 4. RADAR DE TICKETS DE MANTENIMIENTO
    let hasPendingTickets = false;
    try {
      const ticketsRes: any = await lastValueFrom(
        this.http.post(`${crudUrl}/hotel_maintenance_tickets`, {
          operation: 'getall',
          filters: { room_id: room.id, status: 'PENDING' }
        }, { headers: this.adminService.getAuthHeaders() })
      );

      const pendingTickets = Array.isArray(ticketsRes?.data) ? ticketsRes.data : (Array.isArray(ticketsRes) ? ticketsRes : []);
      hasPendingTickets = pendingTickets.some((t: any) => Number(t.room_id) === Number(room.id) && t.status === 'PENDING');
    } catch (error) {
      console.warn('Advertencia: No se pudo verificar el estado de mantenimiento.', error);
    }

    // 5. ACTUALIZAR EL ESTADO DE LA HABITACIÓN
    const nextStatus = hasPendingTickets ? 'maintenance' : 'available';

    const resRoom: any = await lastValueFrom(
      this.http.post(`${crudUrl}/hotel_rooms`, {
        operation: 'update',
        id: room.id,
        fields: {
          status: nextStatus,
          cleaning_status: 'dirty' // Siempre queda sucia
        }
      }, { headers: this.adminService.getAuthHeaders() })
    );

    if (resRoom?.error) {
      throw new Error(`Fallo DB al actualizar habitación: ${resRoom.message}`);
    }

    this.loadRooms();
  }

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

    this.loadRooms();
  }

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
      const start = new Date(checkIn).setHours(0, 0, 0, 0);
      const end = new Date(checkOut).setHours(0, 0, 0, 0);

      const occupiedRoomIds = bookings
        .filter((b: any) => {
          if (excludeId && Number(b.id) === Number(excludeId)) {
            return false;
          }
          const bStart = new Date(b.check_in).setHours(0, 0, 0, 0);
          const bEnd = new Date(b.check_out).setHours(0, 0, 0, 0);
          return (start < bEnd && end > bStart);
        })
        .map((b: any) => b.room_id);

      return allRooms.filter(room => !occupiedRoomIds.includes(room.id));

    } finally {
      this.reportService.loadingReports.set(false);
    }
  }

  public async createFutureReservation(formData: any, roomId: number): Promise<boolean> {
    this.isProcessing.set(true);
    let guestIdToUse: number | null = null;

    try {
      const isFree = await this.isRoomFree(roomId, formData.check_in, formData.check_out);

      if (!isFree) {
        alert('⚠️ ¡ALERTA! La habitación ya fue ocupada o reservada mientras confirmabas.\n\nEl sistema evitó crear un duplicado.');
        this.isProcessing.set(false);
        return false;
      }

      const duplicates: any = await lastValueFrom(
        this.adminService.checkPossibleDuplicate(formData.full_name)
      );

      const realDuplicates = (duplicates.data || []).filter((d: any) => d.id && d.id > 0);

      if (realDuplicates.length > 0) {
        const existingGuest = realDuplicates[0];
        const useExisting = window.confirm(
          `🔍 El huésped "${existingGuest.full_name}" ya existe.\n¿Usar sus datos existentes?`
        );
        if (useExisting) guestIdToUse = existingGuest.id;
      }

      if (!guestIdToUse) {
        let finalDocId = formData.doc_id || this.adminService.generateInternalId();
        let finalEmail = formData.email || this.adminService.generateDummyEmail();

        const guestRes: any = await lastValueFrom(
          this.http.post(`${this.apiUrl_crud}/hotel_guests`, {
            operation: 'insert',
            fields: {
              full_name: formData.full_name,
              phone: formData.phone,
              email: finalEmail,
              doc_id: finalDocId,
              notes: formData.notes,
              id_company: 1
            }
          }, { headers: this.adminService.getAuthHeaders() })
        );
        guestIdToUse = guestRes?.data?.[0]?.id || guestRes?.id;
      }

      if (!guestIdToUse) throw new Error("No se pudo obtener un ID de huésped válido.");

      await lastValueFrom(
        this.http.post(`${this.apiUrl_crud}/hotel_bookings`, {
          operation: 'insert',
          fields: {
            room_id: roomId,
            guest_id: guestIdToUse,
            check_in: formData.check_in,
            check_out: formData.check_out,
            total_amount: formData.total_amount || 0,
            status: formData.status || 'confirmed', // 🛠️ DINÁMICO: 'pending' o 'confirmed'
            payment_status: formData.payment_status || 'pending',
            amount_paid: formData.amount_paid || 0,
            notes: formData.notes || (formData.status === 'pending' ? 'Cotización (Bloqueo Temporal)' : 'Reserva Futura'),
            is_invoiced: formData.is_invoiced || false,
            id_company: 1
          }
        }, { headers: this.adminService.getAuthHeaders() })
      );

      return true;

    } catch (error) {
      console.error(error);
      if (error instanceof Error) alert('Error: ' + error.message);
      throw error;
    } finally {
      this.isProcessing.set(false);
    }
  }

  public async updateReservation(formData: any): Promise<void> {
    this.isProcessing.set(true);
    try {
      // 🧠 LÓGICA DE EVOLUCIÓN FINANCIERA PARA EXTENSIONES
      const currentPaid = Number(formData.amount_paid) || 0;
      const newTotal = Number(formData.total_amount) || 0;
      let newPaymentStatus = formData.payment_status || 'pending';

      // Si el total subió, evaluamos si la cuenta debe pasar de 'paid' a 'partial'
      if (currentPaid >= newTotal && newTotal > 0) {
        newPaymentStatus = 'paid';
      } else if (currentPaid > 0) {
        newPaymentStatus = 'partial';
      } else {
        newPaymentStatus = 'pending';
      }

      await lastValueFrom(
        this.http.post(`${this.apiUrl_crud}/hotel_bookings`, {
          operation: 'update',
          id: formData.id, // 🛠️ ESTRICTAMENTE EN LA RAÍZ
          fields: {
            room_id: formData.room_id,
            check_in: formData.check_in,
            check_out: formData.check_out,
            total_amount: newTotal,
            payment_status: newPaymentStatus, // 🛠️ INYECTAMOS EL NUEVO ESTADO FINANCIERO
            notes: formData.notes,
            is_invoiced: formData.is_invoiced || false
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

  /** Registrar pago parcial o total de una reserva */
  // 🛠️ Se agrega forceConfirm para pagos grupales
  public async registerPayment(booking: any, amountToAdd: number, forceConfirm: boolean = false): Promise<void> {
    this.isProcessing.set(true);
    try {
      const currentPaid = Number(booking.amount_paid) || 0;
      const totalAmount = Number(booking.total_amount) || 0;
      const newPaid = currentPaid + amountToAdd;

      let newPaymentStatus = booking.payment_status;
      if (newPaid >= totalAmount) {
        newPaymentStatus = 'paid';
      } else if (newPaid > 0) {
        newPaymentStatus = 'partial';
      }

      // 🧠 LÓGICA DE EVOLUCIÓN: De Cotización a Reserva Oficial
      let newBookingStatus = booking.status;
      // 🛠️ Ahora evoluciona si hay pago OR si es un pago grupal forzado
      if (booking.status === 'pending' && (newPaid > 0 || forceConfirm)) {
        newBookingStatus = 'confirmed';
      }

      await lastValueFrom(
        this.http.post(`${this.apiUrl_crud}/hotel_bookings`, {
          operation: 'update',
          id: booking.id,
          fields: {
            status: newBookingStatus,
            payment_status: newPaymentStatus,
            amount_paid: newPaid
          }
        }, { headers: this.adminService.getAuthHeaders() })
      );
    } catch (error) {
      console.error("Error al registrar abono:", error);
      throw error;
    } finally {
      this.isProcessing.set(false);
    }
  }

  private async isRoomFree(roomId: number, checkIn: string, checkOut: string): Promise<boolean> {
    const payload = {
      operation: 'getall',
      table_name: 'hotel_bookings',
      fields: { room_id: roomId }
    };

    const res: any = await lastValueFrom(
      this.http.post<ApiResponse<any>>(`${this.apiUrl_crud}/hotel_bookings`, payload, {
        headers: this.adminService.getAuthHeaders()
      })
    );

    const bookings = res.data || [];
    const newStart = new Date(checkIn).setHours(0, 0, 0, 0);
    const newEnd = new Date(checkOut).setHours(0, 0, 0, 0);

    const hasConflict = bookings.some((b: any) => {
      if (b.status === 'cancelled' || b.status === 'checked_out') return false;

      const bStart = new Date(b.check_in).setHours(0, 0, 0, 0);
      const bEnd = new Date(b.check_out).setHours(0, 0, 0, 0);

      return (newStart < bEnd && newEnd > bStart);
    });

    return !hasConflict;
  }

  public async cancelReservation(bookingId: number): Promise<void> {
    this.isProcessing.set(true);
    try {
      await lastValueFrom(
        this.http.post(`${this.apiUrl_crud}/hotel_bookings`, {
          operation: 'update',
          id: bookingId,
          fields: {
            status: 'cancelled'
          }
        }, { headers: this.adminService.getAuthHeaders() })
      );
    } catch (error) {
      console.error("Error al cancelar reserva:", error);
      throw error;
    } finally {
      this.isProcessing.set(false);
    }
  }

  public async confirmPendingReservation(bookingId: number): Promise<void> {
    this.isProcessing.set(true);
    try {
      await lastValueFrom(
        this.http.post(`${this.apiUrl_crud}/hotel_bookings`, {
          operation: 'update',
          id: bookingId,
          fields: {
            status: 'confirmed'
          }
        }, { headers: this.adminService.getAuthHeaders() })
      );
    } catch (error) {
      console.error("Error al confirmar reserva:", error);
      throw error;
    } finally {
      this.isProcessing.set(false);
    }
  }
}