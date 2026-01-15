import { CommonModule } from '@angular/common';
import { Component, input, output } from '@angular/core';

@Component({
  selector: 'app-room-filters',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './room-filters.component.html',
  styleUrl: './room-filters.component.css',
})
export class RoomFiltersComponent {
  currentFilter = input.required<string>();
  isAdmin = input.required<boolean>();

  onFilterChange = output<any>();
  onManageUsers = output<void>();

  filterOptions = [
    { label: 'Todas', value: 'all', activeClass: 'btn-primary' },
    { label: '✅ Disponibles', value: 'available', activeClass: 'btn-success' },
    { label: '🏨 Ocupadas', value: 'occupied', activeClass: 'btn-danger' },
    { label: '🧹 Check-out', value: 'checkout', activeClass: 'btn-warning' },
    { label: '🛠️ Mantenimiento', value: 'maintenance', activeClass: 'btn-secondary' }
  ];
}
