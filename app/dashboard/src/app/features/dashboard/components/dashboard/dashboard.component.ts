import { Component, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { Router } from '@angular/router';
import { HttpClient } from '@angular/common/http';
import { FormsModule } from '@angular/forms';
import { User } from '@core/models/hotel.types';
import { environment } from '@env/environment';
// Componentes Hijos
import { CheckinFormComponent } from '@features/dashboard/components/checkin-form/checkin-form.component';
import { HeaderComponent } from '@features/dashboard/components/header/header.component';
import { RoomCardComponent } from '@features/dashboard/components/room-card/room-card.component';
import { DailyReportModalComponent } from '@features/dashboard/components/daily-report-modal/daily-report-modal.component';
import { RoomFiltersComponent } from '@features/dashboard/components/room-filters/room-filters.component';
import { RoomDetailModalComponent } from '@features/dashboard/components/room-detail-modal/room-detail-modal.component';
import { UserFormModalComponent } from '@features/dashboard/components/user-form-modal/user-form-modal.component';
import { UserListComponent } from '@features/dashboard/components/user-list/user-list.component';
// Servicios
import { AuthService } from '@core/services/auth.service';
import { HotelService } from '@features/dashboard/services/hotel.service';
import { ReportService } from '@features/dashboard/services/report.service';
import { RoomSkeletonComponent } from '@features/dashboard/components/room-skeleton/room-skeleton.component';

@Component({
  selector: 'app-dashboard',
  standalone: true,
  imports: [CommonModule, FormsModule, CheckinFormComponent, HeaderComponent, RoomCardComponent, DailyReportModalComponent, RoomFiltersComponent, RoomDetailModalComponent, UserFormModalComponent, UserListComponent, RoomSkeletonComponent],
  templateUrl: './dashboard.component.html'
})
export class DashboardComponent {
  // 1. INYECCIONES Y CONFIGURACIÓN
  private http = inject(HttpClient);
  private router = inject(Router);
  private authService = inject(AuthService);
  public hotelService = inject(HotelService);
  public reportService = inject(ReportService);

  private readonly N8N_WHATSAPP_WEBHOOK = 'https://n8n.hosting3m.com/webhook/8cd04cee-6a56-4989-b36c-caf9473d7535/webhook';

  // 2. ESTADO (Signals y Variables)
  viewMode = signal<'details' | 'checkin' | 'checkout_validation' | 'user_mgmt'>('details');
  reportFilter = signal<'day' | 'week' | 'month' | 'year'>('day');
  isUserModalOpen = signal(false);
  showReportModal = false;

  activeBooking: any = null;
  dailyReport = { total: 0, paid: 0, pending: 0, transactions: [] as any[], periodLabel: 'Hoy' };

  checkoutChecks = { tvRemote: false, acRemote: false, keys: false, notes: '' };
  tempUser: User = this.getEmptyUser();

  // 3. CICLO DE VIDA Y REFRESH
  ngOnInit() {
    this.refresh();
  }

  refresh() {
    this.hotelService.loadRooms();
    if (this.isAdmin) {
      this.hotelService.loadUsers(this.authService.currentUser()?.id_company);
    }
  }

  // 4. SECCIÓN: GESTIÓN DE HABITACIONES Y RESERVAS (CORE)
  async onSelectRoom(room: any) {
    this.viewMode.set('details');
    this.hotelService.selectRoom(room);
    this.activeBooking = null;

    if (room.status === 'occupied') {
      try {
        this.activeBooking = await this.hotelService.getActiveBooking(room.id);
      } catch (error) {
        console.error('Error al cargar reserva activa:', error);
      }
    }
  }

  async handleCheckinSave(formData: any) {
    const room = this.hotelService.selectedRoom();
    if (!room) return;
    try {
      await this.hotelService.processCheckin(formData, room);
      this.completeActionSuccess(`✅ Check-in exitoso en Hab. ${room.room_number}`);
    } catch (error: any) {
      alert(`Error: ${error.message}`);
    }
  }

  async handleCheckout() {
    const room = this.hotelService.selectedRoom();
    if (!room) return;
    try {
      // Nota: Sería ideal mover este getActiveBooking al HotelService también
      const booking = await this.hotelService.getActiveBooking(room.id);
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

  async confirmFullCheckout() {
    const room = this.hotelService.selectedRoom();
    if (!room || !this.activeBooking) return;
    const reporte = `TV: ${this.checkoutChecks.tvRemote ? '✅' : '❌'}, AC: ${this.checkoutChecks.acRemote ? '✅' : '❌'}. Obs: ${this.checkoutChecks.notes}`;
    try {
      await this.hotelService.processCheckout(room, this.activeBooking.id, reporte, this.checkoutChecks);
      this.completeActionSuccess('✅ Check-out completado.');
    } catch (error) {
      alert('Fallo al procesar el Check-out.');
    }
  }

  async markAsPaid(booking: any) {
    if (!booking || !confirm(`¿Confirmar pago de $${booking.total_amount}?`)) return;
    try {
      await this.hotelService.registerPayment(booking.id);
      if (this.activeBooking?.id === booking.id) {
        this.activeBooking.payment_status = 'paid';
      }
      alert('✅ Pago registrado');
      if (this.showReportModal) this.generateDailyReport();
    } catch (error) {
      alert('Error al registrar pago');
    }
  }

  markAsClean() {
    const room = this.hotelService.selectedRoom();
    if (!room) return;
    // Sugerencia: Mover a hotelService.updateRoomStatus(room.id, 'clean')
    this.hotelService.updateRoomStatus(room.id, 'clean').subscribe(() => {
      this.completeActionSuccess('✨ Habitación lista');
    });
  }

  // 5. SECCIÓN: REPORTES
  async generateDailyReport() {
    try {
      const allBookings = await this.hotelService.getRawBookingsForReport();
      const stats = this.reportService.calculateDailyReport(allBookings, this.reportFilter());
      this.dailyReport = { ...stats, periodLabel: this.getPeriodLabel() };
      this.showReportModal = true;
    } catch (error) {
      alert('Error al generar el reporte.');
    }
  }

  handleReportFilterChange(filter: 'day' | 'week' | 'month' | 'year') {
    this.reportFilter.set(filter);
    this.generateDailyReport();
  }

  // 6. SECCIÓN: USUARIOS
  public get isAdmin(): boolean {
    return this.authService.currentUser()?.role === 'ADMIN';
  }

  openUserManagement() {
    this.viewMode.set('user_mgmt');
    this.hotelService.clearSelection();
    this.hotelService.loadUsers(this.authService.currentUser()?.id_company);
  }

  openNewUserModal() {
    this.hotelService.selectUser(null);
    this.tempUser = this.getEmptyUser();
    this.isUserModalOpen.set(true);
  }

  editUser(user: any) {
    this.hotelService.selectUser(user);
    this.tempUser = { ...user, password: '' };
    this.isUserModalOpen.set(true);
  }

  async handleSaveUser() {
    const selected = this.hotelService.selectedUser();
    const operation = selected ? 'update' : 'insert';
    const id = selected ? selected.email : undefined;
    this.hotelService.saveUser(this.tempUser, operation, id).subscribe({
      next: () => {
        alert('✅ Usuario guardado');
        this.isUserModalOpen.set(false);
        this.hotelService.loadUsers(this.authService.currentUser()?.id_company);
      },
      error: (err) => alert('❌ Error: ' + err.message)
    });
  }

  // 7. SECCIÓN: SISTEMA Y COMUNICACIÓN EXTERNA (n8n / Auth)
  notifyN8N(action: 'checkin' | 'checkout' | 'maintenance' | 'clean_complete' | 'inspected') {
    const room = this.hotelService.selectedRoom();
    if (!room) return;
    const messages: any = { /* ... tus mensajes ... */ };

    if (confirm(messages[action])) {
      const payload = {
        action, room_number: room.room_number, room_id: room.id,
        user: this.authService.currentUser()?.name || 'Recepción'
      };
      this.http.post(this.N8N_WHATSAPP_WEBHOOK, payload).subscribe({
        next: () => this.completeActionSuccess('Estado actualizado correctamente ✅'),
        error: () => alert('Error al conectar con el servidor ❌')
      });
    }
  }

  logout() {
    this.authService.logout();
    this.router.navigate(['/login']);
  }

  // 8. HELPERS / UTILIDADES
  private completeActionSuccess(message: string) {
    alert(message);
    this.viewMode.set('details');
    this.hotelService.clearSelection();
    this.refresh();
  }

  private getEmptyUser(): User {
    return {
      email: '', id_company: 1, names: '', lastname: '',
      phone: '', role: 'EDITOR', password: '', is_active: true,
      created_at: new Date().toISOString()
    };
  }

  getPeriodLabel(): string {
    const labels = { 'day': 'Hoy', 'week': 'Última Semana', 'month': 'Mes Actual', 'year': 'Año Actual' };
    return labels[this.reportFilter()];
  }

  getRoomNumber(id: number): string {
    const found = this.hotelService.rooms().find((r: any) => r.id === id);
    return found ? found.room_number : '??';
  }

  getNights(checkIn: string, checkOut: string): number {
    const start = new Date(checkIn);
    const end = new Date(checkOut);
    const diff = Math.ceil(Math.abs(end.getTime() - start.getTime()) / (1000 * 60 * 60 * 24));
    return diff === 0 ? 1 : diff;
  }

  getSelectedRoomPaymentStatus(): string {
    if (!this.activeBooking) return 'Cargando...';
    return this.activeBooking.payment_status === 'paid' ? '✅' : '⏳';
  }
}