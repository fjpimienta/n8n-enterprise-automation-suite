import { CommonModule } from '@angular/common';
import { Component, computed, input, output } from '@angular/core';
import { Room } from '@core/models/hotel.types';

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
  onReservations = output<void>();

  filterOptions = [
    { label: 'Todas', value: 'all', activeClass: 'btn-primary' },
    { label: '✅ Disponibles', value: 'available', activeClass: 'btn-success' },
    { label: '📅 Reservadas', value: 'reserved', activeClass: 'btn-info' },
    { label: '🏨 Ocupadas', value: 'occupied', activeClass: 'btn-danger' },
    { label: '🧹 Check-out', value: 'checkout', activeClass: 'btn-warning' },
    { label: '🛠️ Mantenimiento', value: 'maintenance', activeClass: 'btn-secondary' }
  ];

  // El computed se queda igual, es perfecto
  reservedCount = computed(() =>
    this.rooms().filter(r => r.status === 'reserved').length
  );

  setFilter(filter: string) {
    this.onFilterChange.emit(filter);
  }
}
