import { CommonModule } from '@angular/common';
import { Component, EventEmitter, inject, input, OnInit, Output, ChangeDetectorRef } from '@angular/core'; // 👈 1. IMPORTAR
import { AssetService } from '@features/admin/services/asset.service';
import { AssetFormModalComponent } from '@features/admin/components/asset-form-modal/asset-form-modal.component';

@Component({
  selector: 'app-room-detail-modal',
  standalone: true,
  imports: [CommonModule, AssetFormModalComponent],
  templateUrl: './room-detail-modal.component.html',
  styleUrl: './room-detail-modal.component.css',
})
export class RoomDetailModalComponent implements OnInit {
  private assetService = inject(AssetService);
  private cdr = inject(ChangeDetectorRef); // 👈 2. INYECTAR EL DETECTOR DE CAMBIOS

  room = input.required<any>();
  activeBooking = input<any>();

  activeTab: string = 'assets';
  roomAssets: any[] = [];

  @Output() onClose = new EventEmitter<void>();
  @Output() onCheckin = new EventEmitter<void>();
  @Output() onCheckout = new EventEmitter<void>();
  @Output() onReservations = new EventEmitter<void>();
  @Output() onPay = new EventEmitter<any>();
  @Output() onMaintenance = new EventEmitter<void>();
  @Output() onFinishMaintenance = new EventEmitter<void>();
  @Output() onMarkAsClean = new EventEmitter<void>();
  @Output() onOpenChecklist = new EventEmitter<void>();

  // Control del modal hijo
  showAssetForm = false;

  ngOnInit() {
    this.loadAssets();
  }

  async loadAssets() {
    // 1. Verificación de seguridad
    const currentRoom = this.room();
    if (!currentRoom || !currentRoom.id) {
      return;
    }

    try {
      // 2. Petición al servicio
      const respuesta = await this.assetService.getAssetsByRoom(currentRoom.id);

      // 3. 🛡️ FILTRO DE SEGURIDAD (Aquí está la corrección)
      // Solo aceptamos objetos que existan y tengan un ID válido (mayor a 0)
      this.roomAssets = (respuesta || []).filter((item: any) => item && item.id);

      // 4. Forzar actualización visual
      this.cdr.detectChanges();

    } catch (error) {
      this.roomAssets = [];
    }
  }

  openAssetForm() {
    this.showAssetForm = true;
  }

  handleAssetSaved() {
    this.showAssetForm = false;
    this.loadAssets();
  }

  isExpired(dateStr: string | undefined): boolean {
    if (!dateStr) return false;
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const expiry = new Date(dateStr);
    return expiry < today;
  }
}