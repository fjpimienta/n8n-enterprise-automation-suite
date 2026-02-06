import { Component, input, output } from '@angular/core';
import { CommonModule } from '@angular/common';

@Component({
  selector: 'app-room-card',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './room-card.component.html',
  styleUrl: './room-card.component.css',
})
export class RoomCardComponent {
  // Input obligatorio tipo 'any' por ahora (idealmente sería Room interface)
  room = input.required<any>();

  // Output al hacer click
  onSelect = output<any>();

  // Lógica visual movida aquí para limpiar el componente padre
  isArrivalToday(): boolean {
    const reservationDate = this.room().next_reservation;
    if (!reservationDate) return false;
    const today = new Date().toISOString().split('T')[0];
    return reservationDate.startsWith(today);
  }
}
