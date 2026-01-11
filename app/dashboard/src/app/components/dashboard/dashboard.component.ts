import { Component, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { AuthService } from '../../services/auth.service';
import { Router } from '@angular/router';
import { HotelService } from '../../services/hotel.service';
import { HttpClient } from '@angular/common/http';
import { CheckinFormComponent } from '../checkin-form/checkin-form.component';
import { environment } from '../../../environments/environment';

@Component({
  selector: 'app-dashboard',
  standalone: true,
  imports: [CommonModule, CheckinFormComponent],
  templateUrl: './dashboard.component.html'
})
export class DashboardComponent {
  private authService = inject(AuthService);
  private router = inject(Router);
  public hotelService = inject(HotelService);
  private http = inject(HttpClient);
  viewMode = signal<'details' | 'checkin'>('details');

  // URL de tu Webhook de n8n para notificaciones
  private readonly N8N_WHATSAPP_WEBHOOK = 'https://tu-n8n.com/webhook/whatsapp-notifications';

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

  onSelectRoom(room: any) {
    this.viewMode.set('details');
    this.hotelService.selectRoom(room);
  }

  // Función que recibe los datos finales del formulario
  async handleCheckinSave(formData: any) {
    const room = this.hotelService.selectedRoom();
    if (!room) return;

    const crudUrl = environment.apiUrl_crud;

    // PREVENCIÓN DE ERRORES DE DATOS VACÍOS
    // 1. Si no hay fecha de check_in, usamos HOY.
    const today = new Date().toISOString().split('T')[0];
    const checkInDate = formData.check_in || today;

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

    this.http.post(`${environment.apiUrl_crud}/hotel_rooms`, {
      operation: 'update',
      filter: { id: room?.id },
      fields: { cleaning_status: 'clean' }
    }).subscribe(() => {
      this.hotelService.clearSelection();
      this.refresh();
    });
  }

}