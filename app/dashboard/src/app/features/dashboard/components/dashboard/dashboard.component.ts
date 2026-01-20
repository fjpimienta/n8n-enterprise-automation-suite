import { Component, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { Router } from '@angular/router';
import { HttpClient } from '@angular/common/http';
import { FormsModule } from '@angular/forms';
import { Guest, User } from '@core/models/hotel.types';
// Componentes Hijos
import { CheckinFormComponent } from '@features/booking/components/checkin-form/checkin-form.component';
import { HeaderComponent } from '@features/dashboard/components/header/header.component';
import { RoomCardComponent } from '@features/dashboard/components/room-card/room-card.component';
import { DailyReportModalComponent } from '@features/finance/components/daily-report-modal/daily-report-modal.component';
import { RoomFiltersComponent } from '@features/dashboard/components/room-filters/room-filters.component';
import { RoomDetailModalComponent } from '@features/booking/components/room-detail-modal/room-detail-modal.component';
import { UserFormModalComponent } from '@features/admin/components/user-form-modal/user-form-modal.component';
import { UserListComponent } from '@features/admin/components/user-list/user-list.component';
import { ReservationFormComponent } from '@features/booking/components/reservation-form/reservation-form.component';
import { SkeletonComponent } from '@shared/ui/loader/skeleton/skeleton.component';
import { GuestFormModalComponent } from '@features/admin/components/guest-form-modal/guest-form-modal.component';
import { GuestListComponent } from '@features/admin/components/guest-list/guest-list.component';
// Servicios
import { AuthService } from '@core/services/auth.service';
import { HotelService } from '@features/dashboard/services/hotel.service';
import { ReportService } from '@features/finance/services/report.service';
import { BookingService } from '@features/booking/services/booking.service';
import { AdminService } from '@features/admin/services/admin.service';

@Component({
  selector: 'app-dashboard',
  standalone: true,
  imports: [CommonModule, FormsModule, CheckinFormComponent, HeaderComponent, RoomCardComponent, DailyReportModalComponent, RoomFiltersComponent, RoomDetailModalComponent, UserFormModalComponent, UserListComponent, GuestFormModalComponent, GuestListComponent, SkeletonComponent, ReservationFormComponent],
  templateUrl: './dashboard.component.html'
})
export class DashboardComponent {
  private http = inject(HttpClient);
  private router = inject(Router);
  private authService = inject(AuthService);
  public hotelService = inject(HotelService);
  public adminService = inject(AdminService);
  public bookingService = inject(BookingService);
  public reportService = inject(ReportService);

  // private readonly N8N_WHATSAPP_WEBHOOK = 'https://n8n.hosting3m.com/webhook/8cd04cee-6a56-4989-b36c-caf9473d7535/webhook';

  viewMode = signal<'details' | 'checkin' | 'checkout_validation' | 'guest_mgmt' | 'user_mgmt' | 'reservation'>('details');
  reportFilter = signal<'day' | 'week' | 'month' | 'year'>('day');
  isUserModalOpen = signal(false);
  isGuestModalOpen = signal(false);
  showReportModal = false;

  activeBooking: any = null;
  dailyReport = { total: 0, paid: 0, pending: 0, transactions: [] as any[], periodLabel: 'Hoy' };

  checkoutChecks = { tvRemote: false, acRemote: false, keys: false, notes: '' };
  tempUser: User = this.getEmptyUser();
  tempGuest: Guest = this.getEmptyGuest();

  ngOnInit() {
    this.refresh();
  }

  /* 1. SECCIÓN: REFRESCO DE DATOS */
  refresh() {
    this.bookingService.loadRooms();
    this.adminService.loadReservations();
    this.adminService.loadGuests();
    if (this.isAdmin) {
      this.adminService.loadUsers(this.authService.currentUser()?.id_company);
    }
  }

  /* 2. SECCIÓN: INTERACCIÓN CON HABITACIONES */
  async onSelectRoom(room: any) {
    this.viewMode.set('details');
    this.hotelService.selectRoom(room);
    this.activeBooking = null;

    // 1. Si el estado es ocupado, buscamos OBLIGATORIAMENTE la estancia de hoy
    if (room.status === 'occupied') {
      const booking = await this.bookingService.getActiveBooking(room.id);
      if (booking && booking.id) {
        this.activeBooking = booking;
      }
    } else {
      const allReservations = this.adminService.reservations();
      // Buscamos si hay reserva para HOY
      const todayStr = new Date().toLocaleDateString('sv-SE');
      /*const res = allReservations.find(r =>
        Number(r.room_id) === Number(room.id) &&
        r.status === 'confirmed' &&
        r.check_in.split(/[ T]/)[0] === todayStr
      );*/
      const res = allReservations.find(r => {
        if (!r.check_in) return false; // Si no tiene fecha, no es el que buscamos

        const reservationDate = r.check_in.split(/[ T]/)[0];
        return Number(r.room_id) === Number(room.id) &&
          r.status === 'confirmed' &&
          reservationDate === todayStr;
      });

      if (res) {
        // OPCIONAL: Si 'res' solo trae guest_id, podrías buscar el nombre del huésped aquí
        // para que el formulario lo muestre de inmediato.
        const guest = this.adminService.guests()?.find(g => g.id === res.guest_id);
        this.activeBooking = {
          ...res,
          guest_name: guest?.full_name,
          guest_phone: guest?.phone,
          guest_email: guest?.email
        };
      }
    }
  }

  /* 3. SECCIÓN: CHECK-IN Y CHECK-OUT */
  async handleCheckinSave(formData: any) {
    const room = this.hotelService.selectedRoom();
    if (!room) return;

    try {
      // 1. Buscamos si hay una reserva HOY para esta habitación en la lista global
      const todayStr = new Date().toLocaleDateString('sv-SE');

      const existingRes = this.adminService.reservations().find(res =>
        Number(res.room_id) === Number(room.id) &&
        res.status === 'confirmed' &&
        res.check_in.split(/[ T]/)[0] === todayStr
      );

      const bookingId = existingRes ? existingRes.id : undefined;

      /*if (bookingId) {
        console.log(`Log: Realizando Check-in sobre reserva existente ID: ${bookingId}`);
      } else {
        console.log('Log: Realizando Check-in como Walk-in (Nueva reserva)');
      }*/

      // 2. Llamamos al servicio pasando el ID si existe
      await this.bookingService.processCheckin(formData, room, bookingId);

      this.completeActionSuccess(`✅ Check-in exitoso en Hab. ${room.room_number}`);
    } catch (error: any) {
      console.error('Error en Check-in:', error);
      alert(`Error: ${error.message}`);
    }
  }

  /* Inicia el proceso de check-out */
  async handleCheckout() {
    const room = this.hotelService.selectedRoom();
    if (!room) return;
    try {
      const booking = await this.bookingService.getActiveBooking(room.id);
      if (booking) {
        this.activeBooking = booking;
        if (booking.payment_status !== 'paid') {
          this.viewMode.set('details');
          alert(`⚠️ Saldo pendiente: $${booking.total_amount}. Registre el pago antes de salir.`);
          return;
        }
      }
      this.checkoutChecks = { tvRemote: false, acRemote: false, keys: false, notes: '' };
      this.viewMode.set('checkout_validation');
    } catch (error) {
      console.error('Error en checkout:', error);
    }
  }

  /* Completa el check-out tras validaciones */
  async confirmFullCheckout() {
    if (!this.checkoutChecks.tvRemote || !this.checkoutChecks.acRemote || !this.checkoutChecks.keys) {
      alert("⚠️ ALERTA: Debe validar la entrega de TV, Aire Acondicionado y Llaves antes de finalizar.");
      return;
    }
    const room = this.hotelService.selectedRoom();
    if (!room || !this.activeBooking) return;
    const reporte = `TV: ${this.checkoutChecks.tvRemote ? '✅' : '❌'}, AC: ${this.checkoutChecks.acRemote ? '✅' : '❌'}. Obs: ${this.checkoutChecks.notes}`;
    try {
      await this.bookingService.processCheckout(room, this.activeBooking.id, reporte, this.checkoutChecks);
      this.completeActionSuccess('✅ Check-out completado.');
    } catch (error) {
      alert('Fallo al procesar el Check-out.');
    }
  }

  /* Marca una reserva como pagada */
  async markAsPaid(booking: any) {
    if (!booking || !confirm(`¿Confirmar pago de $${booking.total_amount}?`)) return;
    try {
      await this.bookingService.registerPayment(booking.id);
      if (this.activeBooking && this.activeBooking.id === booking.id) {
        this.activeBooking.payment_status = 'paid'; // <--- Esto permite que handleCheckout pase la validación
      }
      alert('✅ Pago registrado');
      if (this.showReportModal) this.generateDailyReport();
      this.bookingService.loadRooms();
    } catch (error) {
      alert('Error al registrar pago');
    }
  }

  /* Marca una habitación como limpia */
  markAsClean() {
    const room = this.hotelService.selectedRoom();
    if (!room) return;
    this.hotelService.updateRoomStatus(room.id, 'clean').subscribe(() => {
      this.completeActionSuccess('✨ Habitación lista');
    });
  }

  /* 4. SECCIÓN: REPORTES DIARIOS */
  async generateDailyReport() {
    this.reportService.loadingReports.set(true);
    this.showReportModal = true;
    try {
      const allBookings = await this.reportService.getRawBookingsForReport();
      const stats = this.reportService.calculateDailyReport(allBookings, this.reportFilter());
      this.dailyReport = { ...stats, periodLabel: this.getPeriodLabel() };
    } catch (error) {
      console.error('Error:', error);
    } finally {
      this.reportService.loadingReports.set(false);
    }
  }

  /* Maneja el cambio de filtro en el reporte diario */
  async handleReportFilterChange(filter: 'day' | 'week' | 'month' | 'year') {
    this.reportFilter.set(filter);
    this.generateDailyReport();
  }

  /* 5. SECCIÓN: GESTIÓN DE USUARIOS */
  public get isAdmin(): boolean {
    return this.authService.currentUser()?.role === 'ADMIN';
  }

  /* Abre la vista de gestión de usuarios */
  openUserManagement() {
    this.viewMode.set('user_mgmt');
    this.hotelService.clearSelection();
    this.adminService.loadUsers(this.authService.currentUser()?.id_company);
  }

  /* Abre el modal para crear un nuevo usuario */
  openNewUserModal() {
    this.hotelService.selectUser(null);
    this.tempUser = this.getEmptyUser();
    this.isUserModalOpen.set(true);
  }

  /* Abre el modal para editar un usuario existente */
  editUser(user: any) {
    this.hotelService.selectUser(user);
    this.tempUser = { ...user, password: '' };
    this.isUserModalOpen.set(true);
  }

  /* Guarda los cambios de un usuario (nuevo o editado) */
  async handleSaveUser() {
    const selected = this.hotelService.selectedUser();
    const operation = selected ? 'update' : 'insert';
    const id = selected ? selected.email : undefined;
    this.adminService.saveUser(this.tempUser, operation, id).subscribe({
      next: () => {
        alert('✅ Usuario guardado');
        this.isUserModalOpen.set(false);
        this.adminService.loadUsers(this.authService.currentUser()?.id_company);
      },
      error: (err) => alert('❌ Error: ' + err.message)
    });
  }

  /* 6. SECCIÓN: GESTIÓN DE GUESTS */
  openGuestManagement() {
    this.hotelService.clearSelection();
    this.viewMode.set('guest_mgmt');
  }

  /* Abre el modal para crear un nuevo huésped */
  openNewGuestModal() {
    this.hotelService.selectGuest(null);
    this.tempGuest = this.getEmptyGuest();
    this.isGuestModalOpen.set(true);
  }

  /* Abre el modal para editar un huésped existente */
  editGuest(guest: any) {
    this.hotelService.selectGuest(guest);
    this.tempGuest = { ...guest };
    this.isGuestModalOpen.set(true);
  }

  /* Guarda los cambios de un huésped (nuevo o editado) */
  async handleSaveGuest() {
    const selected = this.hotelService.selectedGuest();
    const operation = selected ? 'update' : 'insert';
    const email = selected ? selected.email : undefined;
    this.adminService.saveGuest(this.tempGuest, operation, email).subscribe({
      next: () => {
        alert('✅ Huésped guardado');
        this.isGuestModalOpen.set(false);
        this.adminService.loadGuests();
      },
      error: (err) => alert('❌ Error: ' + err.message)
    });
  }

  /* 7. SECCIÓN: MANTENIMIENTO DE HABITACIONES */

  /* Abre la vista de reservas */
  openReservations() {
    this.hotelService.clearSelection();
    this.viewMode.set('reservation');
  }

  async reportMaintenance() {
    const room = this.hotelService.selectedRoom();
    if (!room) return;

    // 1. Confirmación visual (Ahora con texto claro)
    if (confirm(`¿Desea reportar la Habitación ${room.room_number} a Mantenimiento?`)) {
      try {
        // 2. Operación de Base de Datos (Tu método async/await)
        await this.hotelService.updateRoomMaintenance(room.id);

        // 3. (OPCIONAL) Notificación externa
        // Si aún quieres mandar el WhatsApp, hazlo como un "extra", no como lo principal
        /*this.http.post(this.N8N_WHATSAPP_WEBHOOK, {
          action: 'maintenance',
          room_number: room.room_number,
          user: this.authService.currentUser()?.name
        }).subscribe();*/ // No necesitamos esperar esto para continuar

        // 4. Éxito visual y refresco
        this.completeActionSuccess('Reporte enviado y habitación en mantenimiento ✅');
        this.hotelService.clearSelection();
        this.refresh();

      } catch (error) {
        console.error('Error:', error);
        alert('Error al actualizar el estado en la base de datos ❌');
      }
    }
  }

  /* Finaliza el mantenimiento de una habitación */
  async handleFinishMaintenance() {
    const room = this.hotelService.selectedRoom();
    if (!room) return;

    if (confirm(`¿Desea marcar la Habitación ${room.room_number} como reparada?`)) {
      try {
        await this.hotelService.finishMaintenance(room.id);
        this.completeActionSuccess('🔧 Mantenimiento finalizado. Enviada a limpieza.');
        this.hotelService.clearSelection();
        this.refresh();
      } catch (error) {
        alert('Error al actualizar el estado ❌');
      }
    }
  }

  // Función simplificada solo para NOTIFICAR
  /*
  sendExternalNotification(action: string) {
    const room = this.hotelService.selectedRoom();
    const payload = {
      action,
      room_number: room?.room_number,
      user: this.authService.currentUser()?.name
    };
    this.http.post(this.N8N_WHATSAPP_WEBHOOK, payload).subscribe();
  }
  */

  /* 8. SECCIÓN: AUTENTICACIÓN Y NAVEGACIÓN */
  logout() {
    this.authService.logout();
    this.router.navigate(['/login']);
  }

  /* Función auxiliar para completar acciones con éxito */
  private completeActionSuccess(message: string) {
    alert(message);
    this.viewMode.set('details');
    this.hotelService.clearSelection();
    this.refresh();
  }

  /* Obtiene un usuario vacío para el formulario */
  private getEmptyUser(): User {
    return {
      email: '', id_company: 1, names: '', lastname: '',
      phone: '', role: 'EDITOR', password: '', is_active: true,
      created_at: new Date().toISOString()
    };
  }

  /* Obtiene un huésped vacío para el formulario */
  private getEmptyGuest(): Guest {
    return {
      id: 0, full_name: '', phone: '', email: '', doc_id: '',
      vip_status: false, created_at: new Date().toISOString(),
      ine_front_url: '', ine_back_url: '', id_company: 1, city: '', state: '',
      country: 'México', notes: '', requires_invoice: false, is_active: true
    };
  }


  /* Obtiene la etiqueta del período para el reporte */
  private getPeriodLabel(): string {
    const labels = { 'day': 'Hoy', 'week': 'Última Semana', 'month': 'Mes Actual', 'year': 'Año Actual' };
    return labels[this.reportFilter()];
  }

  /* Obtiene el número de habitación dado su ID */
  getRoomNumber(id: number): string {
    const found = this.bookingService.rooms().find((r: any) => r.id === id);
    return found ? found.room_number : '??';
  }

  /* Calcula el número de noches entre dos fechas */
  getNights(checkIn: string, checkOut: string): number {
    const start = new Date(checkIn);
    const end = new Date(checkOut);
    const diff = Math.ceil(Math.abs(end.getTime() - start.getTime()) / (1000 * 60 * 60 * 24));
    return diff === 0 ? 1 : diff;
  }

  /* Obtiene el estado de pago de la reserva seleccionada */
  getSelectedRoomPaymentStatus(): string {
    if (!this.activeBooking) return 'Cargando...';
    return this.activeBooking.payment_status === 'paid' ? '✅' : '⏳';
  }

  async markRoomAsClean() {
    const room = this.hotelService.selectedRoom();
    if (!room) return;

    try {
      await this.bookingService.updateCleaningStatus(room.id, 'clean');
      this.completeActionSuccess('✨ Habitación lista para recibir huéspedes');
    } catch (error) {
      alert('Error al actualizar el estado de limpieza');
    }
  }
}