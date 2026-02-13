import { Component, EventEmitter, Output, inject, input } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { AssetService } from '@features/admin/services/asset.service';

@Component({
  selector: 'app-asset-form-modal',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './asset-form-modal.component.html',
  styleUrl: './asset-form-modal.component.scss',
})
export class AssetFormModalComponent {
  private assetService = inject(AssetService);

  roomId = input.required<number>(); // Recibimos el ID de la habitación
  @Output() onClose = new EventEmitter<void>();
  @Output() onSave = new EventEmitter<void>();

  isLoading = false;

  asset = {
    name: '',
    serial_number: '',
    cost: 0,
    purchase_date: new Date().toISOString().split('T')[0], // Hoy
    warranty_expiry: '',
    status: 'ACTIVE',
    current_room_id: 0,
    notes: ''
  };

  async save() {
    if (!this.asset.name || this.asset.cost <= 0) {
      alert('Por favor completa el Nombre y el Costo.');
      return;
    }

    this.isLoading = true;
    try {
      // Asignamos el ID de la habitación automáticamente
      this.asset.current_room_id = this.roomId();

      await this.assetService.saveAsset(this.asset);

      this.onSave.emit(); // Avisamos que guardamos
      this.onClose.emit(); // Cerramos
      alert('✅ Activo asignado correctamente');
    } catch (error) {
      console.error(error);
      alert('Error al guardar el activo');
    } finally {
      this.isLoading = false;
    }
  }
}