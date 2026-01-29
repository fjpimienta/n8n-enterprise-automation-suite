import { CommonModule } from '@angular/common';
import { Component, computed, inject, input, output } from '@angular/core';
import { Room } from '@core/models/hotel.types';
import { BookingService } from '@features/booking/services/booking.service';

@Component({
  selector: 'app-room-filters',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './room-filters.component.html',
  styleUrl: './room-filters.component.css',
})
export class RoomFiltersComponent {
  currentFilter = input.required<string>();
  rooms = input<Room[]>([]);
  isAdmin = input.required<boolean>();

  onFilterChange = output<any>();
  onManageUsers = output<void>();
  onManageGuests = output<void>();
  onReservations = output<void>();

  public bookingService = inject(BookingService);

  filterOptions = [
    // { label: 'Todas', value: 'all', activeClass: 'btn-primary' },
    { label: '🟢 Disponible', value: 'available', activeClass: 'btn-success' },
    { label: '🔒 Ocupada', value: 'occupied', activeClass: 'btn-danger' },
    { label: '🗑️ Limpieza', value: 'dirty', activeClass: 'btn-warning' },
    { label: '🔧 Mantenimiento', value: 'maintenance', activeClass: 'btn-secondary' },
    { label: '📅 Reservada', value: 'reserved', activeClass: 'btn-info' }
  ];

  setFilter(filter: string) {
    this.onFilterChange.emit(filter);
  }

  onSearch(event: Event) {
    const input = event.target as HTMLInputElement;
    this.bookingService.searchQuery.set(input.value);
  }

  clearSearch() {
    this.bookingService.searchQuery.set('');
  }
}
