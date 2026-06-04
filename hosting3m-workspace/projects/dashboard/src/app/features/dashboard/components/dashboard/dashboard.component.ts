import { ChangeDetectionStrategy, Component, computed, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { Router } from '@angular/router';
import { FormsModule } from '@angular/forms';
import { Booking, Guest, Room, User } from '@core/models/hotel.types';
// Componentes Hijos
import { CheckinFormComponent } from '@features/booking/components/checkin-form/checkin-form.component';
import { CheckoutFormComponent } from '@features/booking/components/checkout-form/checkout-form.component';
import { RoomCardComponent } from '@features/dashboard/components/room-card/room-card.component';
import { RoomFiltersComponent } from '@features/dashboard/components/room-filters/room-filters.component';
import { RoomDetailModalComponent } from '@features/booking/components/room-detail-modal/room-detail-modal.component';
import { UserFormModalComponent } from '@features/admin/components/user-form-modal/user-form-modal.component';
import { UserListComponent } from '@features/admin/components/user-list/user-list.component';
import { ReservationManagerComponent } from '@features/booking/components/reservation-manager/reservation-manager.component';
import { SkeletonComponent } from '@shared/ui/loader/skeleton/skeleton.component';
import { GuestFormModalComponent } from '@features/admin/components/guest-form-modal/guest-form-modal.component';
import { GuestListComponent } from '@features/admin/components/guest-list/guest-list.component';
import { RoomChecklistModalComponent } from '@features/booking/components/room-checklist-modal/room-checklist-modal.component';
import { ExpenseFormModalComponent } from '@features/finance/components/expense-form-modal/expense-form-modal.component';
import { MaintenanceTicketModalComponent } from '@features/dashboard/components/maintenance-ticket-modal/maintenance-ticket-modal.component';
import { MaintenanceMonitorModalComponent } from '@features/dashboard/components/maintenance-monitor-modal/maintenance-monitor-modal.component';
// Servicios
import { AuthService, TenantService } from 'core-auth';
import { HotelService } from '@features/dashboard/services/hotel.service';
import { ReportService } from '@features/finance/services/report.service';
import { BookingService } from '@features/booking/services/booking.service';
import { AdminService } from '@features/admin/services/admin.service';
import { lastValueFrom } from 'rxjs';
import { ApiResponse } from '@core/interfaces/api-response.interface';

@Component({
  selector: 'app-dashboard',
  standalone: true,
  imports: [CommonModule, FormsModule, CheckinFormComponent, CheckoutFormComponent, RoomCardComponent,
    RoomFiltersComponent, RoomDetailModalComponent, UserFormModalComponent, UserListComponent, GuestFormModalComponent, GuestListComponent,
    SkeletonComponent, ReservationManagerComponent, RoomChecklistModalComponent, ExpenseFormModalComponent, MaintenanceTicketModalComponent,
    MaintenanceMonitorModalComponent],
  templateUrl: './dashboard.component.html',
  changeDetection: ChangeDetectionStrategy.OnPush
})
export class DashboardComponent {
  private router = inject(Router);
  private authService = inject(AuthService);
  public tenantService = inject(TenantService);
  public hotelService = inject(HotelService);
  public adminService = inject(AdminService);
  public bookingService = inject(BookingService);
  public reportService = inject(ReportService);

  // private readonly N8N_WHATSAPP_WEBHOOK = 'https://n8n.hosting3m.com/webhook/8cd04cee-6a56-4989-b36c-caf9473d7535/webhook';

  viewMode = signal<'details' | 'checkin' | 'checkout_validation' | 'guest_mgmt' | 'user_mgmt' | 'reservation' | 'checklist'>('details');
  reportFilter = signal<'day' | 'week' | 'month' | 'year'>('day');
  isUserModalOpen = signal(false);
  isGuestModalOpen = signal(false);
  isExpenseModalOpen = signal(false);
  showReportModal = false;
  collapsedGroups = signal<Set<string>>(new Set());
  expandedGroups = signal<Set<string>>(new Set());
  maintenanceRoom = signal<Room | null>(null);
  showMaintenanceMonitor = false;
  maintenanceFilterRoomId: number | null = null;

  activeBooking = signal<Booking | any>(null);

  tempUser: User = this.getEmptyUser();
  tempGuest: Guest = this.getEmptyGuest();

  dailyReport = {
    total_sales: 0,
    paid_in: 0,
    pending: 0,
    total_expenses: 0,
    balance: 0,
    transactions: [] as any[],
    expenseTransactions: [] as any[],
    periodLabel: 'Hoy'
  };

  /** Computed para evitar evaluación en cada CD */
  readonly isAdmin = computed(() => this.authService.hasRole('ADMIN'));
  /**  Esta función decide qué icono, color y texto mostrar cuando la lista está vacía.  */
  emptyStateConfig = computed(() => {
    const filter = this.bookingService.filter();

    const configs: Record<string, { icon: string; title: string; description: string; color: string }> = {
      'available': {
        icon: 'ti ti-hotel',
        title: 'No hay habitaciones disponibles',
        description: 'Todas las habitaciones están ocupadas, en limpieza o reportadas.',
        color: 'text-success'
      },
      'occupied': {
        icon: 'ti ti-door-open',
        title: 'El hotel está vacío',
        description: 'No hay huéspedes registrados en este momento.',
        color: 'text-danger'
      },
      'dirty': {
        icon: 'ti ti-vacuum-cleaner',
        title: '¡Todo está impecable!',
        description: 'No hay habitaciones pendientes de limpieza. ¡Buen trabajo!',
        color: 'text-warning'
      },
      'maintenance': {
        icon: 'ti ti-mood-crazy-happy',
        title: '¡Cero reportes operativos!',
        description: 'Todas las habitaciones funcionan perfectamente. ¡Excelente mantenimiento!',
        color: 'text-secondary'
      },
      'reserved': {
        icon: 'ti ti-luggage',
        title: 'Sin llegadas para hoy',
        description: 'No se esperan más huéspedes por reserva este día.',
        color: 'text-info'
      },
      'checkout_today': {
        icon: 'ti ti-logout',
        title: 'Sin salidas para hoy',
        description: 'Ningún huésped tiene programada su salida el día de hoy.',
        color: 'text-orange'
      },
      'all': {
        icon: 'ti ti-ghost',
        title: 'Vaya, esto está vacío',
        description: 'No se encontraron habitaciones con este criterio.',
        color: 'text-muted'
      }
    };

    return configs[filter] || configs['all'];
  });

  ngOnInit() {
    this.hotelService.selectRoom(null as any);
    this.refresh();
  }

  refresh() {
    this.bookingService.loadRooms();
    this.adminService.loadReservations();
  }

  /* 1. SECCIÓN: REFRESCO Y RETORNO AL INICIO */
  refreshMain() {
    this.viewMode.set('details');
    this.hotelService.clearSelection();
    this.activeBooking.set(null);
    this.bookingService.filter.set('all');

    this.showMaintenanceMonitor = false;
    this.maintenanceFilterRoomId = null;

    this.refresh();
  }

  /* 2. SECCIÓN: INTERACCIÓN CON HABITACIONES */
  async onSelectRoom(room: Room) {
    if (room.status === 'maintenance') {
      this.maintenanceFilterRoomId = room.id;
      this.showMaintenanceMonitor = true;
      return;
    }

    this.viewMode.set('details');
    this.hotelService.selectRoom(room);
    this.activeBooking.set(null);

    const booking = await this.bookingService.findActiveOrTodayReservation(room);
    if (booking) {
      this.activeBooking.set(booking);
    }
  }

  /* 3. SECCIÓN: CHECK-IN Y CHECK-OUT */
  async handleCheckinSave(formData: any) {
    const room = this.hotelService.selectedRoom();
    if (!room) return;

    try {
      let bookingId = undefined;
      const active = this.activeBooking();

      // 1. Extraer ID validando que no sea una reserva del futuro
      if (active) {
        const now = new Date();
        const todayStr = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`;
        const checkInStr = String(active.check_in).split(/[ T]/)[0];

        if (checkInStr <= todayStr || active.status === 'checked_in') {
          bookingId = active.id;
        }
      }

      // 2. Fallback
      if (!bookingId) {
        const now = new Date();
        const todayStr = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`;
        const existingRes = this.adminService.reservations().find(res =>
          Number(res.room_id) === Number(room.id) &&
          (res.status === 'confirmed' || res.status === 'pending') &&
          res.check_in.split(/[ T]/)[0] <= todayStr &&
          res.check_out.split(/[ T]/)[0] > todayStr
        );
        bookingId = existingRes ? existingRes.id : undefined;
      }

      // ... continúa el resto de la función: await this.bookingService.processCheckin...

      // 3. Procesamos y ESPERAMOS validación estricta de base de datos
      await this.bookingService.processCheckin(formData, room, bookingId);

      this.completeActionSuccess(`✅ Check-in exitoso en Hab. ${room.room_number}`);
    } catch (error: any) {
      console.error('Error en Check-in:', error);
      alert(`❌ Operación Rechazada por el Sistema:\n${error.message}`);
    }
  }

  /* Inicia el proceso de check-out */
  async startCheckoutProcess() {
    const room = this.hotelService.selectedRoom();
    if (!room) return;

    try {
      // Buscamos la reserva activa
      const booking = await this.bookingService.getActiveBooking(room.id);

      if (booking) {
        this.activeBooking.set(booking);

        // Validación de negocio: No dejar salir si no pagó
        if (booking.payment_status !== 'paid') {
          // Si quieres ser estricto, muestra alerta y no cambies de vista
          alert(`⚠️ Saldo pendiente: $${booking.total_amount}. Registre el pago antes de salir.`);
          // Opcional: Podrías retornar aquí si quieres bloquear el flujo
          return;
        }

        // Si todo ok, cambiamos la vista para mostrar el componente hijo
        this.viewMode.set('checkout_validation');
      }
    } catch (error) {
      console.error('Error al iniciar checkout:', error);
    }
  }

  onCheckoutSuccess() {
    alert('✅ Check-out completado exitosamente.');
    this.viewMode.set('details');
    this.hotelService.clearSelection();
    this.refresh(); // Recargamos el grid de habitaciones
  }

  // 👇 AÑADE ESTE NUEVO MÉTODO JUSTO DEBAJO
  onReservationUpdated() {
    this.viewMode.set('details');
    this.hotelService.clearSelection();
    this.refresh(); // 🔥 ESTO ES LO QUE OBLIGA AL DASHBOARD A PINTAR LOS CAMBIOS
  }

  onCheckoutCancel() {
    this.viewMode.set('details');
  }

  /* Registra un abono o liquida una reserva */
  async markAsPaid(eventPayload: { booking: Booking | any, amount: number }) {
    if (!eventPayload || !eventPayload.booking || !eventPayload.amount) return;

    try {
      await this.bookingService.registerPayment(eventPayload.booking, eventPayload.amount);

      const currentPaid = Number(eventPayload.booking.amount_paid) || 0;
      const newPaid = currentPaid + eventPayload.amount;
      const totalAmount = Number(eventPayload.booking.total_amount) || 0;
      const newStatus = newPaid >= totalAmount ? 'paid' : 'partial';

      const currentActive = this.activeBooking();
      if (currentActive && currentActive.id === eventPayload.booking.id) {
        this.activeBooking.update(val => ({
          ...val,
          payment_status: newStatus,
          amount_paid: newPaid
        }));
      }

      alert(`✅ Abono de $${eventPayload.amount} registrado exitosamente.`);

      if (this.showReportModal) this.generateDailyReport();
      this.bookingService.loadRooms();

      if (newStatus === 'paid') {
        this.hotelService.clearSelection();
        this.viewMode.set('details');
      }

    } catch (error) {
      alert('❌ Error al registrar el abono.');
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
  // Cuando el usuario da clic en "Semana" en el modal
  handleReportFilterChange(filter: 'day' | 'week' | 'month' | 'year') {
    this.reportFilter.set(filter); // 1. Actualiza el signal
    this.generateDailyReport();    // 2. Recalcula los datos con el nuevo filtro
  }

  /* La función de generación actualizada (Alineada al Server-Side Filtering) */
  async generateDailyReport() {
    this.reportService.loadingReports.set(true);
    this.showReportModal = true;
    try {
      // 1. Calculamos las fechas que el Dashboard quiere ver
      const dates = this.reportService.getPeriodDates(this.reportFilter());

      // 2. Pedimos los datos filtrados por RED (Pasando los nuevos argumentos)
      const [allBookings, allExpenses] = await Promise.all([
        this.reportService.getRawBookingsForReport(dates.start, dates.end),
        this.reportService.getRawExpensesForReport(dates.start, dates.end)
      ]);

      // 3. Calculamos el reporte final
      const stats = this.reportService.calculateDailyReport(allBookings, allExpenses, this.reportFilter());

      this.dailyReport = stats; // Asignamos el resultado completo
    } catch (error) {
      console.error('Error:', error);
    } finally {
      this.reportService.loadingReports.set(false);
    }
  }

  /* 5. SECCIÓN: GESTIÓN DE USUARIOS */

  openUserManagement() {
    this.viewMode.set('user_mgmt');
    this.hotelService.clearSelection();
  }

  openNewUserModal() {
    this.hotelService.selectUser(null);
    this.tempUser = this.getEmptyUser();
    this.isUserModalOpen.set(true);
  }

  editUser(user: User) {
    this.hotelService.selectUser(user);
    this.tempUser = { ...user, password: '' };
    this.isUserModalOpen.set(true);
  }

  async handleSaveUser() {
    const selected = this.hotelService.selectedUser();
    const operation = selected ? 'update' : 'insert';
    const id = selected ? selected.email : undefined;
    this.adminService.saveUser(this.tempUser, operation, id).subscribe({
      next: () => {
        alert('✅ Usuario guardado');
        this.isUserModalOpen.set(false);
        this.adminService.loadUsers(this.tenantService.activeTenantId() as number);
      },
      error: (err) => alert('❌ Error: ' + err.message)
    });
  }

  /* 6. SECCIÓN: GESTIÓN DE GUESTS */
  openGuestManagement() {
    this.hotelService.clearSelection();
    this.viewMode.set('guest_mgmt');

    this.showMaintenanceMonitor = false;
    this.maintenanceFilterRoomId = null;
  }

  openNewGuestModal() {
    this.hotelService.selectGuest(null);
    this.tempGuest = this.getEmptyGuest();
    this.isGuestModalOpen.set(true);
  }

  editGuest(guest: Guest) {
    this.hotelService.selectGuest(guest);
    this.tempGuest = { ...guest };
    this.isGuestModalOpen.set(true);
  }

  /* Guarda los cambios de un huésped (nuevo o editado) */
  private generateInternalId(): string {
    // Retorna algo como: INT-1706289452123 (INT + Timestamp en milisegundos)
    return `INT-${Date.now()}`;
  }

  /* Genera un email ficticio único si es necesario */
  private generateDummyEmail(): string {
    // Retorna: no-email-1706289452123@hosting3m.com
    return `no-email-${Date.now()}@hosting3m.com`;
  }

  async handleSaveGuest() {
    try {
      await this.adminService.saveGuestWithValidation(
        this.tempGuest,
        this.hotelService.selectedGuest()
      );

      alert('✅ Huésped guardado correctamente');
      this.isGuestModalOpen.set(false);
      this.adminService.loadGuests(this.tenantService.activeTenantId() as number);
    } catch (error: any) {
      if (error.message === 'OPERACION_CANCELADA_POR_DUPLICADO') return;
      console.error('Error al guardar huésped:', error);
      alert('❌ Error: ' + error.message);
    }
  }

  /* 7. SECCIÓN: MANTENIMIENTO DE HABITACIONES */

  /* Abre la vista de reservas */
  openReservations() {
    this.hotelService.clearSelection();
    this.viewMode.set('reservation');

    this.showMaintenanceMonitor = false;
    this.maintenanceFilterRoomId = null;
  }

  async reportMaintenance() {
    const room = this.hotelService.selectedRoom();
    if (!room) return;

    // 1. Cerramos el modal actual de detalles de la habitación
    this.hotelService.clearSelection();

    // 2. Abrimos el modal oficial de creación de Tickets 
    this.openMaintenanceReport(room);
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

  /* Maneja la respuesta directa desde el Monitor de Mantenimiento */
  handleMonitorResolved() {
    // 1. Cerramos el monitor
    this.showMaintenanceMonitor = false;
    this.maintenanceFilterRoomId = null;

    // 2. Lanzamos la alerta y recargamos la vista automáticamente
    this.completeActionSuccess('🔧 Falla reparada. Habitación disponible y limpia.');
  }

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
      email: '',
      id_company: this.tenantService.activeTenantId() as number, // 🚀 FIX DINÁMICO
      names: '', lastname: '',
      phone: '', role: 'EDITOR', password: '', is_active: true,
      created_at: new Date().toISOString()
    };
  }

  /* Obtiene un huésped vacío para el formulario */
  private getEmptyGuest(): Guest {
    return {
      id: 0, full_name: '', phone: '', email: '', doc_id: '',
      vip_status: false, created_at: new Date().toISOString(),
      ine_front_url: '', ine_back_url: '',
      id_company: this.tenantService.activeTenantId() as number, // 🚀 FIX DINÁMICO
      city: '', state: '',
      country: 'México', notes: '', requires_invoice: false, is_active: true
    };
  }


  /* Obtiene la etiqueta del período para el reporte */
  private getPeriodLabel(): string {
    const labels = { 'day': 'Hoy', 'week': 'Última Semana', 'month': 'Mes Actual', 'year': 'Año Actual' };
    return labels[this.reportFilter()];
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
    const booking = this.activeBooking(); // <--- Leemos el Signal con ()
    if (!booking) return 'Cargando...';
    return booking.payment_status === 'paid' ? '✅' : '⏳';
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

  toggleGroup(groupKey: string) {
    this.expandedGroups.update(set => {
      const newSet = new Set(set);
      if (newSet.has(groupKey)) {
        newSet.delete(groupKey); // Cerrar
      } else {
        newSet.add(groupKey);    // Abrir
      }
      return newSet;
    });
  }

  isExpanded(groupKey: string): boolean {
    // UX MEJORADA: Si el usuario está buscando algo en el buscador, 
    // FORZAMOS la expansión para que encuentre la habitación.
    if (this.bookingService.searchQuery().trim().length > 0) {
      return true;
    }
    return this.expandedGroups().has(groupKey);
  }

  handleChecklistSave(apiResponse: ApiResponse<any>) {
    // 1. CORRECCIÓN: Validamos que apiResponse no sea null/undefined antes de leer .error
    if (!apiResponse || apiResponse.error) {
      const msg = apiResponse?.message || 'Error desconocido del servidor';
      alert('❌ Error al guardar el rondín: ' + msg);
      return;
    }

    // 2. Extraer los datos reales
    const savedRecord = apiResponse.data && apiResponse.data.length > 0 ? apiResponse.data[0] : null;

    if (savedRecord) {
      const obs = savedRecord.observaciones || savedRecord.checklist_data?.observaciones;
      const statusText = obs ? '⚠️ Con Observaciones' : '✅ Todo OK';
      alert(`Rondín guardado correctamente.\nEstado: ${statusText}`);
    } else {
      // Si llegó hasta aquí con éxito pero sin data devuelta (a veces pasa en inserts)
      alert('✅ Rondín registrado con éxito.');
    }

    // 3. Cerrar
    this.viewMode.set('details');
  }

  openMaintenanceReport(room: Room) {
    this.maintenanceRoom.set(room);
  }

  /* Función para cancelar una reserva desde el modal del rack */
  async handleCancelReservation(booking: any) {
    if (!booking || !booking.id) return;

    // Validación estricta por seguridad
    const guestName = booking.hotel_guests_data?.full_name || booking.guest_name || 'este huésped';
    const confirm = window.confirm(`¿Estás seguro de cancelar la reserva de ${guestName}?\n\nEsta acción liberará la habitación y no se puede deshacer.`);

    if (!confirm) return;

    try {
      await this.bookingService.cancelReservation(booking.id);
      this.completeActionSuccess('🚫 Reserva cancelada exitosamente.');
    } catch (error) {
      alert('❌ Ocurrió un error al intentar cancelar la reserva.');
    }
  }

  /* 🧠 QUICK EXTEND: Extensión rápida de estancias */
  async handleQuickExtend() {
    const room = this.hotelService.selectedRoom();
    const booking = this.activeBooking();
    if (!room || !booking) return;

    // 🛠️ FIX 1: Limpiar las fechas de la Base de Datos que traen hora (e.g. "2026-04-13 00:00:00+00")
    const rawCheckOut = String(booking.check_out).split(/[ T]/)[0];
    const rawCheckIn = String(booking.check_in).split(/[ T]/)[0];

    // 1. Preguntamos los días con un UX limpio
    const currentOutFormat = new Date(rawCheckOut + 'T12:00:00').toLocaleDateString('es-MX');
    const input = window.prompt(
      `🏨 AMPLIAR ESTANCIA\n\n` +
      `Fecha de salida actual: ${currentOutFormat}\n\n` +
      `¿Cuántas noches EXTRA desea agregar?`,
      '1'
    );

    if (input === null) return; // El usuario canceló

    const extraNights = parseInt(input, 10);
    if (isNaN(extraNights) || extraNights <= 0) {
      alert('❌ Ingrese un número válido de noches.');
      return;
    }

    try {
      // 2. Calcular la nueva fecha matemáticamente
      const currentOutDate = new Date(rawCheckOut + 'T12:00:00');
      currentOutDate.setDate(currentOutDate.getDate() + extraNights);

      const year = currentOutDate.getFullYear();
      const month = String(currentOutDate.getMonth() + 1).padStart(2, '0');
      const day = String(currentOutDate.getDate()).padStart(2, '0');
      const newCheckOutStr = `${year}-${month}-${day}`;

      // 3. 🛡️ REGLA DE NEGOCIO: Validar que la habitación no esté apartada
      const availableRooms = await this.bookingService.checkAvailability(
        rawCheckOut, // Checamos a partir de la salida original
        newCheckOutStr,
        [room],
        booking.id
      );

      if (availableRooms.length === 0) {
        alert(`⚠️ No se puede extender.\nLa habitación ya está reservada por otro huésped a partir del ${currentOutFormat}.`);
        return;
      }

      // 4. Recálculo Financiero Automático
      const baseExtraCost = extraNights * room.price_night;
      const totalExtraCost = booking.is_invoiced ? (baseExtraCost * 1.18) : baseExtraCost;

      const currentTotal = Number(booking.total_amount) || 0;
      const currentPaid = Number(booking.amount_paid) || 0;
      const newTotal = currentTotal + totalExtraCost;

      let newPaymentStatus = 'pending';
      if (currentPaid >= newTotal) newPaymentStatus = 'paid';
      else if (currentPaid > 0) newPaymentStatus = 'partial';

      // 5. Preparar actualización a Base de Datos
      const updateData = {
        id: booking.id,
        room_id: room.id,
        check_in: rawCheckIn,      // 🛠️ FIX 2: Mandamos entrada limpia
        check_out: newCheckOutStr, // Nueva salida calculada (YYYY-MM-DD)
        total_amount: newTotal,
        amount_paid: currentPaid,
        payment_status: newPaymentStatus,
        notes: booking.notes,
        is_invoiced: booking.is_invoiced
      };

      // Esperamos respuesta de la BD
      await this.bookingService.updateReservation(updateData);

      const newDebt = newTotal - currentPaid;
      alert(`✅ Estancia extendida exitosamente por ${extraNights} noche(s).\n\nSaldo pendiente a cobrar: $${newDebt.toFixed(2)}`);

      // 6. Refrescar el Dashboard para mostrar los cambios instantáneamente
      this.hotelService.clearSelection();
      this.viewMode.set('details');
      this.refresh();

    } catch (error) {
      console.error('Error al extender:', error);
      alert('❌ Ocurrió un error al intentar extender la estancia.');
    }
  }
}