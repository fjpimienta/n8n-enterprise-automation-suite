import { Component, inject, signal, computed, OnInit, OnDestroy, effect } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ReservationFormComponent } from '../reservation-form/reservation-form.component';
import { AdminService } from '@features/admin/services/admin.service';
import { HotelService } from '@features/dashboard/services/hotel.service';
import { BookingService } from '@features/booking/services/booking.service';
import { PdfExportConfig, PdfExportService } from 'ui-pdf-export';

@Component({
  selector: 'app-reservation-manager',
  standalone: true,
  imports: [CommonModule, ReservationFormComponent],
  templateUrl: './reservation-manager.component.html'
})
export class ReservationManagerComponent implements OnInit, OnDestroy {
  public adminService = inject(AdminService);
  public hotelService = inject(HotelService);
  private bookingService = inject(BookingService);
  private pdfService = inject(PdfExportService);

  selectedIds = signal<Set<number>>(new Set());
  selectedReservation = signal<any | null>(null);

  // Estados de interfaz
  isLoading = signal(true);
  private initCacheCleared = false;
  private fallbackTimeout: any;

  currentPage = signal(1);
  itemsPerPage = 8;

  filteredReservations = computed(() => {
    const all = this.adminService.reservations();
    const selectedRoom = this.hotelService.selectedRoom();

    const now = new Date();
    const year = now.getFullYear();
    const month = String(now.getMonth() + 1).padStart(2, '0');
    const day = String(now.getDate()).padStart(2, '0');
    const todayStr = `${year}-${month}-${day}`;

    return all
      .filter(res => {
        if (!res.check_out) return false;

        const checkoutDateStr = String(res.check_out).split(/[ T]/)[0];
        const status = String(res.status || '').toLowerCase().trim();

        const matchesDate = (status === 'checked_in') ||
          (['confirmed', 'pending'].includes(status) && checkoutDateStr >= todayStr);

        if (selectedRoom) {
          return matchesDate && Number(res.room_id) === Number(selectedRoom.id);
        }
        return matchesDate;
      })
      .sort((a, b) => {
        const dateA = new Date(String(a.check_in).replace(' ', 'T')).getTime();
        const dateB = new Date(String(b.check_in).replace(' ', 'T')).getTime();
        return (dateA || 0) - (dateB || 0);
      });
  });

  paginatedReservations = computed(() => {
    const startIndex = (this.currentPage() - 1) * this.itemsPerPage;
    return this.filteredReservations().slice(startIndex, startIndex + this.itemsPerPage);
  });

  totalPages = computed(() => Math.ceil(this.filteredReservations().length / this.itemsPerPage));

  constructor() {
    // 🧠 DETECCIÓN INTELIGENTE DE CARGA
    effect(() => {
      const resLength = this.adminService.reservations().length;

      // 1. Detectamos el momento en que loadReservations() limpia el arreglo para refrescar
      if (resLength === 0) {
        this.initCacheCleared = true;
      }

      // 2. Si ya se limpió y acaba de llegar la nueva data de n8n, apagamos el spinner de inmediato.
      if (this.initCacheCleared && resLength > 0) {
        this.isLoading.set(false);
        if (this.fallbackTimeout) clearTimeout(this.fallbackTimeout);
      }
    }, { allowSignalWrites: true });
  }

  ngOnInit() {
    this.isLoading.set(true);
    this.initCacheCleared = false;

    this.adminService.loadReservations();
    if (this.bookingService.rooms().length === 0) {
      this.bookingService.loadRooms();
    }

    // 3. Fallback de Seguridad: Si la base de datos realmente está en 0 y nunca llega info,
    // quitamos el spinner a los 2.5 segundos para mostrar el estado vacío permanentemente.
    this.fallbackTimeout = setTimeout(() => {
      this.isLoading.set(false);
    }, 2500);
  }

  ngOnDestroy() {
    this.clearFilters();
    if (this.fallbackTimeout) clearTimeout(this.fallbackTimeout);
  }

  getRoomNumber(id: number): string {
    const found = this.bookingService.rooms().find((r: any) => r.id === id);
    return found ? found.room_number : 'N/A';
  }

  nextPage() {
    if (this.currentPage() < this.totalPages()) this.currentPage.update(p => p + 1);
  }

  prevPage() {
    if (this.currentPage() > 1) this.currentPage.update(p => p - 1);
  }

  editReservation(res: any) {
    const room = this.bookingService.rooms().find(r => r.id === res.room_id);
    if (room) {
      this.hotelService.selectRoom(room);
    }
    this.selectedReservation.set(res);
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  onReservationSaved() {
    this.selectedReservation.set(null);
    this.hotelService.selectRoom(null as any);
    this.adminService.loadReservations();
  }

  focusNewReservation() {
    this.selectedReservation.set(null);
    this.hotelService.selectRoom(null as any);
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  toggleSelection(id: number, event: any) {
    const current = new Set(this.selectedIds());
    if (event.target.checked) current.add(id);
    else current.delete(id);
    this.selectedIds.set(current);
  }

  toggleAll(event: any) {
    const current = new Set(this.selectedIds());
    const visibleItems = this.paginatedReservations();

    if (event.target.checked) {
      visibleItems.forEach(r => current.add(r.id));
    } else {
      visibleItems.forEach(r => current.delete(r.id));
    }
    this.selectedIds.set(current);
  }

  isAllSelected(): boolean {
    const visibleItems = this.paginatedReservations();
    if (visibleItems.length === 0) return false;
    return visibleItems.every(r => this.selectedIds().has(r.id));
  }

  printSelected() {
    const ids = this.selectedIds();
    if (ids.size === 0) {
      alert('Seleccione al menos una reserva para imprimir.');
      return;
    }

    const rawReservations = this.adminService.reservations().filter(r => ids.has(r.id));
    const reportItems = this.mapToPdfItems(rawReservations);
    const clientName = rawReservations[0]?.hotel_guests_data?.full_name || 'Cliente Mostrador';

    const pdfConfig: PdfExportConfig = {
      fileName: `Cotizacion_${clientName}`,
      title: 'PRESUPUESTO DE HOSPEDAJE',
      companyName: 'Hotel San José',
      companyAddress: 'Av. Juarez s/n, Centro, Catazajá, Chiapas',
      clientName: clientName,
      clientSubtitle: 'Estancia Solicitada',
      items: reportItems,
      footerTitle: 'Forma de Pago',
      footerText: [
        'Transferencia a nombre de: Diana Perez Pimienta | RFC: PEED8001019A1',
        'Banco BBVA | CLABE: 012180015615151108 | No. Cuenta: 1561515110',
      ]
    };

    this.pdfService.generate(pdfConfig);
  }

  private mapToPdfItems(reservations: any[]): any[] {
    const groups: any = {};

    reservations.forEach(res => {
      const room = this.bookingService.rooms().find(r => r.id === res.room_id);
      const type = room?.type || 'Estándar';

      const s = new Date(res.check_in).getTime();
      const e = new Date(res.check_out).getTime();
      let nights = Math.ceil((e - s) / (1000 * 3600 * 24));
      if (nights < 1) nights = 1;

      const price = room?.price_night || 0;
      const key = `${type}-${price}-${nights}`;

      if (!groups[key]) {
        groups[key] = {
          concept: `Habitación ${type}`,
          description: `${nights} Noche(s)`,
          quantity: 0,
          unitPrice: price * nights,
          total: 0
        };
      }
      groups[key].quantity += 1;
      groups[key].total += (price * nights);
    });

    return Object.values(groups);
  }

  clearFilters() {
    this.selectedReservation.set(null);
    this.hotelService.selectRoom(null as any);
  }

  async cancelReservation(reservation: any) {
    const confirm = window.confirm(`¿Cancelar la reserva de ${reservation.hotel_guests_data?.full_name || 'este huésped'}?`);
    if (!confirm) return;

    try {
      await this.bookingService.cancelReservation(reservation.id);
      alert('✅ Reserva cancelada.');
      this.adminService.loadReservations();
    } catch (error) {
      alert('❌ Error al cancelar.');
    }
  }

  async confirmReservation(reservation: any) {
    const guestName = reservation.hotel_guests_data?.full_name || reservation.guest_name || 'este huésped';

    const confirm = window.confirm(
      `🔔 ATENCIÓN: Aprobación de Reserva Web\n\n` +
      `Huésped: ${guestName}\n` +
      `Estancia: ${new Date(reservation.check_in).toLocaleDateString()} al ${new Date(reservation.check_out).toLocaleDateString()}\n\n` +
      `⚠️ IMPORTANTE: ¿Ya validaste la recepción del anticipo o pago total?\n\n` +
      `Al presionar 'Aceptar', la habitación quedará OFICIALMENTE CONFIRMADA y bloqueada en el inventario. No confirmes si el pago sigue pendiente.`
    );

    if (!confirm) return;

    try {
      await this.bookingService.confirmPendingReservation(reservation.id);
      alert('✅ Reserva web confirmada exitosamente en el calendario.');
      this.adminService.loadReservations();
      this.bookingService.loadRooms();
    } catch (error) {
      alert('❌ Error al confirmar la reserva.');
    }
  }
}