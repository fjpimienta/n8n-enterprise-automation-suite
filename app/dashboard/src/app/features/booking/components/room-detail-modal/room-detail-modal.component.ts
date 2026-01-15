import { CommonModule } from '@angular/common';
import { Component, EventEmitter, input, Output, output } from '@angular/core';

@Component({
  selector: 'app-room-detail-modal',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './room-detail-modal.component.html',
  styleUrl: './room-detail-modal.component.css',
})
export class RoomDetailModalComponent {


  @Output() onMaintenance = new EventEmitter<void>();
  @Output() onFinishMaintenance = new EventEmitter<void>();

  room = input.required<any>();
  activeBooking = input<any>();

  onClose = output<void>();
  onCheckin = output<void>();
  onCheckout = output<void>();
  onPay = output<any>();
  // onMaintenance = output<void>();
}
