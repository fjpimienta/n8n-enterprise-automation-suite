import { Component, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { AuthService } from '../../services/auth.service';
import { Router } from '@angular/router';
import { HotelService } from '../../services/hotel.service';
import { HttpClient } from '@angular/common/http';
import { CheckinFormComponent } from '../checkin-form/checkin-form.component';
import { environment } from '../../../environments/environment';
import { FormsModule } from '@angular/forms';

@Component({
  selector: 'app-dashboard',
  standalone: true,
  imports: [CommonModule, CheckinFormComponent, FormsModule],
  templateUrl: './dashboard.component.html'
})
export class DashboardComponent {
  private authService = inject(AuthService);
  private router = inject(Router);
  public hotelService = inject(HotelService);
  private http = inject(HttpClient);
  viewMode = signal<'details' | 'checkin' | 'checkout_validation'>('details');

  // URL de tu Webhook de n8n para notificaciones
  private readonly N8N_WHATSAPP_WEBHOOK = 'https://n8n.hosting3m.com/webhook/8cd04cee-6a56-4989-b36c-caf9473d7535/webhook';

  checkoutChecks = {
    tvRemote: false,
    acRemote: false,
    keys: false,
    notes: ''
  };
  activeBooking: any = null;

  // Variables para el reporte
  showReportModal = false;
  dailyReport = {
    total: 0,
    paid: 0,
    pending: 0,
    transactions: [] as any[] // Lista de reservas de hoy
  };

  ngOnInit() {
    this.refresh();
  }

  refresh() {
    this.hotelService.loadRooms();
  }

  logout() {
    this.authService.logout();
    this.router.navigate(['/login']);
  }

  async onSelectRoom(room: any) {
    this.viewMode.set('details');
    this.hotelService.selectRoom(room);
    this.activeBooking = null; // Reset anterior

    if (room.status === 'occupied') {
      try {
        // Buscamos la reserva confirmada para esta habitación
        const res: any = await this.http.post(`${environment.apiUrl_crud}/hotel_bookings`, {
          operation: 'getall',
          fields: {
            room_id: room.id,
            status: 'confirmed'
          }
        }).toPromise();

        if (res.data && res.data.length > 0) {
          this.activeBooking = res.data[0];
        }
      } catch (error) {
        console.error('Error al cargar reserva activa:', error);
      }
    }
  }

  // Función que recibe los datos finales del formulario
  async handleCheckinSave(formData: any) {
    const room = this.hotelService.selectedRoom();
    if (!room) return;

    const crudUrl = environment.apiUrl_crud;

    // PREVENCIÓN DE ERRORES DE DATOS VACÍOS
    // 1. Si no hay fecha de check_in, usamos HOY.
    const now = new Date().toISOString(); // Esto da YYYY-MM-DDTHH:mm:ssZ
    const checkInDate = formData.check_in || now;

    // 2. Aseguramos que check_out no sea nulo (opcional: poner fecha de mañana por defecto)
    if (!formData.check_out) {
      alert("Por favor selecciona una fecha de salida (Check-out).");
      return;
    }

    try {
      // ------------------------------------------
      // PASO 1: INSERTAR/ACTUALIZAR HUÉSPED
      // ------------------------------------------
      // Ahora que n8n tiene el ON CONFLICT (doc_id), esto devolverá el usuario existente
      // en lugar de un error.
      const guestRes: any = await this.http.post(`${crudUrl}/hotel_guests`, {
        operation: 'insert',
        fields: {
          full_name: formData.full_name,
          phone: formData.phone,
          doc_id: formData.doc_id,
          id_company: 1,
          email: formData.email || null,
          city: formData.city || null,
          state: formData.state || null,
          notes: formData.notes || null,
          country: formData.country || 'México'
        }
      }).toPromise();

      // Lógica robusta para encontrar el ID en la respuesta de n8n
      let guestId = null;

      // 1. Si guestRes es un objeto que tiene 'data' y 'data' es un Array (Tu caso actual según log)
      if (guestRes?.data && Array.isArray(guestRes.data) && guestRes.data.length > 0) {
        guestId = guestRes.data[0].id;
      }
      // 2. Si guestRes es un Array que contiene un objeto con propiedad 'data'
      else if (Array.isArray(guestRes) && guestRes[0]?.data && Array.isArray(guestRes[0].data)) {
        guestId = guestRes[0].data[0].id;
      }
      // 3. Si guestRes es un Array directo de registros
      else if (Array.isArray(guestRes) && guestRes.length > 0) {
        guestId = guestRes[0].id;
      }
      // 4. Si guestRes es un objeto con ID directo o envuelto simple
      else {
        guestId = guestRes?.id || guestRes?.data?.id;
      }

      if (!guestId) {
        console.error('Estructura no reconocida en guestRes:', guestRes);
        throw new Error("El sistema no devolvió el ID del huésped. Revisa la consola.");
      }

      console.log('✅ Huésped procesado. ID:', guestId);

      // ------------------------------------------
      // PASO 2: CREAR RESERVA
      // ------------------------------------------
      await this.http.post(`${crudUrl}/hotel_bookings`, {
        operation: 'insert',
        fields: {
          room_id: room.id,
          guest_id: guestId,
          check_in: checkInDate, // Variable segura (no null)
          check_out: formData.check_out,
          total_amount: formData.total_amount || 0, // Evitar nulls en montos
          status: 'confirmed',
          payment_status: 'pending',
          id_company: 1
        }
      }).toPromise();

      // ------------------------------------------
      // PASO 3: ACTUALIZAR HABITACIÓN
      // ------------------------------------------
      // Agregamos 'room_number' porque es NOT NULL en la base de datos
      await this.http.post(`${crudUrl}/hotel_rooms`, {
        operation: 'insert',
        fields: {
          id: room.id,
          room_number: room.room_number, // <--- CRÍTICO: Evita error de restricción not-null
          type: room.type,               // Opcional, pero recomendado
          price_night: room.price_night, // Opcional
          status: 'occupied',
          cleaning_status: 'clean'
        }
      }).toPromise();

      // ÉXITO
      alert(`✅ Check-in exitoso. Habitación ${room.room_number} ocupada.`);
      this.viewMode.set('details');
      this.hotelService.clearSelection();
      this.refresh();

    } catch (error: any) {
      console.error('❌ Error CRÍTICO en Check-in:', error);
      // Mostrar mensaje más amigable si es posible
      const msg = error.error?.message || error.message || 'Error desconocido';
      alert(`Falló el registro: ${msg}`);
    }
  }

  // 3. Modifica la función que abre el checkout
  handleCheckout() {
    // En lugar de hacer el proceso, abrimos el modal de validación
    this.checkoutChecks = { tvRemote: false, acRemote: false, keys: false, notes: '' }; // Reset
    this.viewMode.set('checkout_validation');
  }

  // 4. Crea la función final que se ejecuta tras validar
  async confirmFullCheckout() {
    const room = this.hotelService.selectedRoom();
    if (!room) return;

    try {
      const crudUrl = environment.apiUrl_crud;

      // PASO A: Buscar la reserva activa
      const bookingRes: any = await this.http.post(`${crudUrl}/hotel_bookings`, {
        operation: 'getall',
        fields: { room_id: room.id, status: 'confirmed' }
      }).toPromise();

      const booking = Array.isArray(bookingRes.data) ? bookingRes.data[0] : null;

      if (booking) {
        // Creamos el reporte de texto para la columna 'notes'
        const reporte = `INVENTARIO: TV: ${this.checkoutChecks.tvRemote ? '✅' : '❌'}, ` +
          `AC: ${this.checkoutChecks.acRemote ? '✅' : '❌'}, ` +
          `Llaves: ${this.checkoutChecks.keys ? '✅' : '❌'}. ` +
          `Obs: ${this.checkoutChecks.notes}`;

        // PASO B: Actualizar la reserva incluyendo los campos de inventario
        await this.http.post(`${crudUrl}/hotel_bookings`, {
          operation: 'update',
          id: booking.id,
          fields: {
            status: 'checked_out',
            check_out: new Date().toISOString(),
            notes: reporte,
            // MAPEO DE CAMPOS BOOLEANOS A LA BASE DE DATOS
            inventory_tv_ok: this.checkoutChecks.tvRemote,
            inventory_ac_ok: this.checkoutChecks.acRemote,
            inventory_keys_ok: this.checkoutChecks.keys
          }
        }).toPromise();
      }

      // PASO C: Liberar la habitación y marcarla como SUCIA
      await this.http.post(`${crudUrl}/hotel_rooms`, {
        operation: 'update',
        id: room.id,
        fields: {
          status: 'available',
          cleaning_status: 'dirty'
        }
      }).toPromise();

      alert('✅ Check-out exitoso. Inventario registrado en base de datos.');
      this.viewMode.set('details');
      this.hotelService.clearSelection();
      this.refresh();

    } catch (error) {
      console.error('Error en Check-out:', error);
      alert('Fallo al procesar el Check-out.');
    }
  }

  private executeCheckin(data: any) {
    this.http.post(this.N8N_WHATSAPP_WEBHOOK, { action: 'checkin_full', ...data })
      .subscribe({
        next: () => {
          alert('Check-in registrado exitosamente ✅');
          this.hotelService.clearSelection();
          this.refresh();
        },
        error: () => alert('Error al procesar el registro')
      });
  }

  // Nueva función para botones de acción
  notifyN8N(action: 'checkin' | 'checkout' | 'maintenance' | 'clean_complete' | 'inspected') {
    const room = this.hotelService.selectedRoom();
    if (!room) return;

    // Definimos los mensajes asegurando que cubran todas las acciones posibles
    const messages: Record<'checkin' | 'checkout' | 'maintenance' | 'clean_complete' | 'inspected', string> = {
      checkin: `¿Confirmar ingreso (Check-in) en Habitación ${room.room_number}?`,
      checkout: `¿Confirmar salida (Check-out) de Habitación ${room.room_number}? La habitación pasará a estado SUCIA.`,
      maintenance: `¿Enviar Habitación ${room.room_number} a mantenimiento?`,
      clean_complete: `¿Confirmar que la Habitación ${room.room_number} ya está limpia?`,
      inspected: `¿Confirmar que la Habitación ${room.room_number} ha sido inspeccionada y está lista para venta?`
    };

    if (confirm(messages[action])) {
      const payload = {
        action: action,
        room_number: room.room_number,
        room_id: room.id,
        user: this.authService.currentUser()?.name || 'Recepción'
      };

      this.http.post(this.N8N_WHATSAPP_WEBHOOK, payload).subscribe({
        next: () => {
          alert('Estado actualizado correctamente ✅');
          this.hotelService.clearSelection();
          this.refresh();
        },
        error: () => alert('Error al conectar con el servidor ❌')
      });
    }
  }

  // Dentro de tu DashboardComponent
  isArrivalToday(reservationDate?: string): boolean {
    if (!reservationDate) return false;

    const today = new Date().toISOString().split('T')[0]; // Formato YYYY-MM-DD
    return reservationDate.startsWith(today);
  }

  markAsClean() {
    const room = this.hotelService.selectedRoom();
    if (!room) return;

    this.http.post(`${environment.apiUrl_crud}/hotel_rooms`, {
      operation: 'update',
      id: room.id, // El Query Builder ahora busca el ID aquí
      fields: { cleaning_status: 'clean' }
    }).subscribe(() => {
      alert('✨ Habitación lista');
      this.hotelService.clearSelection();
      this.refresh();
    });
  }

  async markAsPaid(booking: any) {
    if (!booking || !confirm(`¿Confirmar que recibiste el pago de $${booking.total_amount}?`)) return;

    try {
      const crudUrl = environment.apiUrl_crud;

      await this.http.post(`${crudUrl}/hotel_bookings`, {
        operation: 'update',
        id: booking.id,
        fields: { payment_status: 'paid' }
      }).toPromise();

      // Actualizamos la reserva en memoria para que el cambio sea instantáneo en la vista
      if (this.activeBooking && this.activeBooking.id === booking.id) {
        this.activeBooking.payment_status = 'paid';
      }

      alert('✅ Pago registrado correctamente.');

      // Opcional: refrescar el reporte de caja si estaba abierto
      if (this.showReportModal) {
        this.generateDailyReport();
      }

    } catch (error) {
      console.error('Error al registrar pago:', error);
      alert('No se pudo registrar el pago.');
    }
  }

  // Función para traducir ID -> Número de Habitación
  getRoomNumber(id: number): string {
    // Accedemos a la lista de habitaciones que ya tiene el servicio
    // NOTA: Si hotelService.rooms es un array simple, quita los paréntesis ()
    const roomsList = this.hotelService.rooms();

    const found = roomsList.find((r: any) => r.id === id);
    return found ? found.room_number : '??';
  }

  // Función para generar el Reporte de Caja
  async generateDailyReport() {
    const crudUrl = environment.apiUrl_crud;

    // 1. Obtenemos la fecha de hoy en formato local YYYY-MM-DD
    const today = new Date().toISOString().split('T')[0];

    try {
      // 2. Pedimos TODAS las reservas (luego filtraremos en memoria para mayor precisión)
      // Nota: Si tienes miles de reservas, esto se debe filtrar desde n8n, 
      // pero para empezar así es más rápido y fácil.
      const res: any = await this.http.post(`${crudUrl}/hotel_bookings`, {
        operation: 'getall',
        fields: { id_company: 1 } // Traemos todo lo de la empresa
      }).toPromise();

      const bookings = Array.isArray(res.data) ? res.data : [];

      // 3. Filtramos solo las de HOY (creadas hoy O check-out hoy)
      const todaysBookings = bookings.filter((b: any) => {
        // Opción A: Ventas generadas hoy (Created At)
        const createdDate = b.created_at ? b.created_at.split('T')[0] : '';

        // Opción B: Dinero que entra hoy (Check-in o Check-out)
        // Usaremos 'created_at' para saber lo que se VENDIÓ hoy.
        return createdDate === today;
      });

      // 4. Sumamos los totales
      this.dailyReport = {
        total: 0,
        paid: 0,
        pending: 0,
        transactions: todaysBookings
      };

      todaysBookings.forEach((b: any) => {
        const amount = parseFloat(b.total_amount || 0);
        this.dailyReport.total += amount;
        const status = b.payment_status?.toLowerCase();

        if (status === 'paid') {
          this.dailyReport.paid += amount;
        } else {
          this.dailyReport.pending += amount;
        }
      });

      // 5. Abrimos el modal
      this.showReportModal = true;

    } catch (error) {
      console.error('Error generando reporte:', error);
      alert('No se pudo calcular el corte de caja.');
    }
  }

  // Función para obtener el estado de pago de la habitación seleccionada
  getSelectedRoomPaymentStatus(): string {
    if (!this.activeBooking) return 'Cargando...';

    return this.activeBooking.payment_status === 'paid'
      ? '✅'
      : '⏳';
  }

  getNights(checkIn: string, checkOut: string): number {
    const start = new Date(checkIn);
    const end = new Date(checkOut);
    const diffTime = Math.abs(end.getTime() - start.getTime());
    const diffDays = Math.ceil(diffTime / (1000 * 60 * 60 * 24));
    return diffDays === 0 ? 1 : diffDays; // Si es el mismo día, cuenta como 1 noche
  }

}