import { Component, inject, signal, input, Output, EventEmitter, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { AdminService } from '@features/admin/services/admin.service';
import { HotelService } from '@features/dashboard/services/hotel.service';
import { BookingService } from '@features/booking/services/booking.service';
import { ReservationFormComponent } from '../reservation-form/reservation-form.component';

@Component({
  selector: 'app-reservation-manager',
  standalone: true,
  imports: [CommonModule, ReservationFormComponent],
  templateUrl: './reservation-manager.component.html'
})
export class ReservationManagerComponent {
  public adminService = inject(AdminService);
  public hotelService = inject(HotelService);
  private bookingService = inject(BookingService);

  @Output() onClose = new EventEmitter<void>();
  @Output() onSaved = new EventEmitter<void>();

  selectedReservation = signal<any | null>(null);

  // Paginación local
  currentPage = signal(1);
  itemsPerPage = 5;

  // Lógica de filtrado y paginación movida aquí
  filteredReservations = computed(() => {
    const all = this.adminService.reservations();
    const selectedRoom = this.hotelService.selectedRoom();
    const today = new Date();
    today.setHours(0, 0, 0, 0);

    return all
      .filter(res => {
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
    // Buscamos la habitación asociada para que el formulario sepa cuál es
    const room = this.bookingService.rooms().find(r => r.id === res.room_id);
    if (room) {
      this.hotelService.selectRoom(room);
    }
    this.selectedReservation.set(res);
  }

  onReservationSaved() {
    this.selectedReservation.set(null);
    this.onSaved.emit();
  }

  // Dentro de tu ReservationManagerComponent
  focusNewReservation() {
    // 1. Reseteamos la reserva seleccionada para que el formulario se ponga en modo "Nuevo"
    this.selectedReservation.set(null);

    // 2. Opcional: Si quieres que el cursor se mueva automáticamente al campo de fecha
    const entryDateInput = document.querySelector('input[type="date"]') as HTMLElement;
    if (entryDateInput) {
      entryDateInput.focus();
    }
  }
}