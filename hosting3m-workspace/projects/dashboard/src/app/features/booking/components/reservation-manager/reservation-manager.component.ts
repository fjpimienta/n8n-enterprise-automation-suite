import { Component, inject, signal, computed, OnInit } from '@angular/core';
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
export class ReservationManagerComponent implements OnInit {
  public adminService = inject(AdminService);
  public hotelService = inject(HotelService);
  private bookingService = inject(BookingService);
  private pdfService = inject(PdfExportService);

  selectedIds = signal<Set<number>>(new Set());
  selectedReservation = signal<any | null>(null);

  currentPage = signal(1);
  itemsPerPage = 8;

  filteredReservations = computed(() => {
    const all = this.adminService.reservations();
    const selectedRoom = this.hotelService.selectedRoom();
    const today = new Date();
    today.setHours(0, 0, 0, 0);

    return all
      .filter(res => {
        if (!res.check_out) return false;

        const checkoutDate = new Date(res.check_out);
        const matchesDate = res.status === 'confirmed' && checkoutDate >= today;

        if (selectedRoom) {
          return matchesDate && Number(res.room_id) === Number(selectedRoom.id);
        }
        return matchesDate;
      })
      .sort((a, b) => new Date(a.check_in).getTime() - new Date(b.check_in).getTime());
  });

  paginatedReservations = computed(() => {
    const startIndex = (this.currentPage() - 1) * this.itemsPerPage;
    return this.filteredReservations().slice(startIndex, startIndex + this.itemsPerPage);
  });

  totalPages = computed(() => Math.ceil(this.filteredReservations().length / this.itemsPerPage));

  ngOnInit() {
    this.adminService.loadReservations();
    if (this.bookingService.rooms().length === 0) {
      this.bookingService.loadRooms();
    }
  }

  ngOnDestroy() {
    this.clearFilters();
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

  // 1. Marcar/Desmarcar una sola fila
  toggleSelection(id: number, event: any) {
    const current = new Set(this.selectedIds());
    if (event.target.checked) current.add(id);
    else current.delete(id);
    this.selectedIds.set(current);
  }

  // 2. Marcar/Desmarcar TODAS las visibles
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

  // 3. Verificar si todo está seleccionado (para el checkbox maestro)
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

    // 1. Filtrar reservas
    const rawReservations = this.adminService.reservations().filter(r => ids.has(r.id));

    // 2. Mapear (Usando el helper que ya tienes o agregaremos abajo)
    const reportItems = this.mapToPdfItems(rawReservations);

    // 3. Obtener nombre cliente
    const clientName = rawReservations[0]?.hotel_guests_data?.full_name || 'Cliente Mostrador';

    // 4. CONFIGURACIÓN COMPLETA (Esto corrige el error de Type '{}')
    const pdfConfig: PdfExportConfig = {
      fileName: `Cotizacion_${clientName}`,
      title: 'PRESUPUESTO DE HOSPEDAJE',

      // Datos de TU Hotel (Emisor)
      companyName: 'Hotel San José',
      companyAddress: 'Av. Juarez s/n, Centro, Catazajá, Chiapas',

      // Datos del Cliente
      clientName: clientName,
      clientSubtitle: 'Estancia Solicitada',

      // Los ítems procesados
      items: reportItems,

      // Opcionales (puedes omitirlos si quieres, pero pon el objeto completo si los declaras)
      footerTitle: 'Forma de Pago',
      footerText: [
        'Transferencia a nombre de: Diana Perez Pimienta | RFC: PEED8001019A1',
        'Banco BBVA | CLABE: 012180015615151108 | No. Cuenta: 1561515110',
      ]
    };

    // 5. Generar
    this.pdfService.generate(pdfConfig);
  }

  // --- HELPER DE MAPEO NECESARIO ---
  // (Asegúrate de tener este método en tu clase también)
  private mapToPdfItems(reservations: any[]): any[] { // Usa 'any[]' temporalmente si PdfExportItem no se importa bien, o impórtalo.
    const groups: any = {};

    reservations.forEach(res => {
      const room = this.bookingService.rooms().find(r => r.id === res.room_id);
      const type = room?.type || 'Estándar';

      // Calculo de noches
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

  // --- NUEVO MÉTODO PARA LIMPIAR EL FILTRO ---
  clearFilters() {
    this.selectedReservation.set(null);
    this.hotelService.selectRoom(null as any);
  }
}