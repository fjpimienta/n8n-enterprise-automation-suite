import { CommonModule } from '@angular/common';
import { Component, EventEmitter, input, Output } from '@angular/core';

@Component({
  selector: 'app-room-detail-modal',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './room-detail-modal.component.html',
  styleUrl: './room-detail-modal.component.css',
})
export class RoomDetailModalComponent {

  room = input.required<any>();
  activeBooking = input<any>();

  @Output() onClose = new EventEmitter<void>();
  @Output() onCheckin = new EventEmitter<void>();
  @Output() onCheckout = new EventEmitter<void>();
  @Output() onReservations = new EventEmitter<void>();
  @Output() onPay = new EventEmitter<any>();
  @Output() onMaintenance = new EventEmitter<void>();
  @Output() onFinishMaintenance = new EventEmitter<void>();
  @Output() onMarkAsClean = new EventEmitter<void>();

}