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
    { label: '🏨 Ocupadas', value: 'occupied', activeClass: 'btn-danger' },
    { label: '🧹 Sucia', value: 'dirty', activeClass: 'btn-warning' },
    { label: '🛠️ Mantenimiento', value: 'maintenance', activeClass: 'btn-secondary' }
  ];


  setFilter(filter: string) {
    this.onFilterChange.emit(filter);
  }
}
