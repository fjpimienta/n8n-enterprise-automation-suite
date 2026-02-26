import { CommonModule } from '@angular/common';
import { ChangeDetectionStrategy, Component, input, output } from '@angular/core';

/** Tipo de unión literal para el filtro de habitaciones; alineado con BookingService.filter */
export type RoomFilterStatus = 'all' | 'available' | 'occupied' | 'dirty' | 'maintenance' | 'reserved';

@Component({
  selector: 'app-room-filters',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './room-filters.component.html',
  styleUrl: './room-filters.component.css',
  changeDetection: ChangeDetectionStrategy.OnPush
})
export class RoomFiltersComponent {
  currentFilter = input.required<RoomFilterStatus>();
  searchQuery = input<string>('');
  isAdmin = input.required<boolean>();

  onFilterChange = output<RoomFilterStatus>();
  onSearchChange = output<string>();
  onManageUsers = output<void>();
  onManageGuests = output<void>();
  onReservations = output<void>();

  filterOptions: { label: string; value: RoomFilterStatus; activeClass?: string }[] = [
    { label: '🟢 Disponible', value: 'available', activeClass: 'btn-success' },
    { label: '🔒 Ocupada', value: 'occupied', activeClass: 'btn-danger' },
    { label: '🗑️ Limpieza', value: 'dirty', activeClass: 'btn-warning' },
    { label: '🔧 Mantenimiento', value: 'maintenance', activeClass: 'btn-secondary' },
    { label: '📅 Llegadas Hoy', value: 'reserved', activeClass: 'btn-info' }
  ];

  setFilter(filter: RoomFilterStatus) {
    this.onFilterChange.emit(filter);
  }

  onSearch(event: Event) {
    const inputEl = event.target as HTMLInputElement;
    this.onSearchChange.emit(inputEl.value);
  }

  clearSearch() {
    this.onSearchChange.emit('');
  }
}
