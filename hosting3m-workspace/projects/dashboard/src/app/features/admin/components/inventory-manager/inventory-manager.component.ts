import { Component, inject, OnInit, signal, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { BookingService } from '@features/booking/services/booking.service';
import { AssetFormModalComponent } from '../asset-form-modal/asset-form-modal.component';
import { AssetService } from '@features/admin/services/asset.service';

@Component({
  selector: 'app-inventory-manager',
  standalone: true,
  imports: [CommonModule, FormsModule, AssetFormModalComponent],
  templateUrl: './inventory-manager.component.html'
})
export class InventoryManagerComponent implements OnInit {
  private assetService = inject(AssetService);
  private bookingService = inject(BookingService);

  // Datos locales (ya que el servicio devuelve promesas, el componente guarda el estado)
  assets = signal<any[]>([]);
  isLoading = signal(true);

  // Filtros UI
  searchTerm = signal('');
  filterStatus = signal('ALL');

  // Modal
  isModalOpen = signal(false);
  currentAsset = signal<any>({});
  isEditing = signal(false);

  // KPIs Computados
  totalAssets = computed(() => this.assets().length);
  totalValue = computed(() => this.assets().reduce((acc, a) => acc + (Number(a.cost) || 0), 0));
  damagedAssets = computed(() => this.assets().filter(a => a.status === 'DAMAGED' || a.status === 'MISSING').length);

  // Lista Filtrada
  filteredAssets = computed(() => {
    let list = this.assets();
    const search = this.searchTerm().toLowerCase();
    const status = this.filterStatus();

    if (status !== 'ALL') {
      list = list.filter(a => a.status === status);
    }

    if (search) {
      list = list.filter(a =>
        (a.name && a.name.toLowerCase().includes(search)) ||
        (a.serial_number && a.serial_number.toLowerCase().includes(search))
      );
    }
    return list;
  });

  ngOnInit() {
    this.loadData();
    this.bookingService.loadRooms(); // Para mapear IDs a Nombres de Habitación
  }

  async loadData() {
    this.isLoading.set(true);
    try {
      const data = await this.assetService.getAssets();
      this.assets.set(data);
    } catch (error) {
      console.error(error);
    } finally {
      this.isLoading.set(false);
    }
  }

  getRoomNumber(id: number) {
    if (!id) return 'Bodega';
    const room = this.bookingService.rooms().find(r => r.id == id);
    return room ? `Hab. ${room.room_number}` : 'Desconocido';
  }

  openModal(asset: any = null) {
    if (asset) {
      this.currentAsset.set({ ...asset });
      this.isEditing.set(true);
    } else {
      // Nota: current_room_id null = Bodega
      this.currentAsset.set({ name: '', status: 'GOOD', current_room_id: null, category: 'ELECTRONICA' });
      this.isEditing.set(false);
    }
    this.isModalOpen.set(true);
  }

  async saveAsset() {
    try {
      const asset = this.currentAsset();
      // Si estamos editando pasamos el ID, si no undefined
      const id = this.isEditing() ? asset.id : undefined;

      await this.assetService.saveAsset(asset, id);

      this.isModalOpen.set(false);
      this.loadData(); // Recargar lista
      alert('✅ Inventario actualizado');
    } catch (e) {
      console.error(e);
      alert('Error al guardar');
    }
  }
}