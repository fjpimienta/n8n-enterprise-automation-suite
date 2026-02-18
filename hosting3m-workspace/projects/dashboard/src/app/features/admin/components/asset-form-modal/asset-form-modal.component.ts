import { CommonModule } from '@angular/common';
import { Component, input, model, output, inject, OnInit, effect } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { BookingService } from '@features/booking/services/booking.service'; // Para listar habitaciones

@Component({
  selector: 'app-asset-form-modal',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './asset-form-modal.component.html',
})
export class AssetFormModalComponent implements OnInit {
  bookingService = inject(BookingService);

  isOpen = input.required<boolean>();
  assetData = model.required<any>();
  isEditing = input<boolean>(false);

  onClose = output<void>();
  onSave = output<void>();

  ngOnInit() {
    // Cargar habitaciones si no están cargadas (para el select de ubicación)
    if (this.bookingService.rooms().length === 0) {
      this.bookingService.loadRooms();
    }
  }
}