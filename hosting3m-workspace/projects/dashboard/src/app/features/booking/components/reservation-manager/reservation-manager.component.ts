import { Component, inject, signal, computed, OnInit } from '@angular/core';
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
export class ReservationManagerComponent implements OnInit {
  public adminService = inject(AdminService);
  public hotelService = inject(HotelService);
  private bookingService = inject(BookingService);

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
}