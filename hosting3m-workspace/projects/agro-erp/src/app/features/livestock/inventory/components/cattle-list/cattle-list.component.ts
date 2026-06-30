import { Component, inject, OnInit, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { CattleDetailModalComponent } from '../cattle-detail-modal/cattle-detail-modal.component';
import { CattleApiService } from '@core/services/cattle-api.service';
import { TenantService } from 'core-auth';
import { CattleDataService } from '@core/services/cattle-data.service';

@Component({
  selector: 'app-cattle-list',
  standalone: true,
  imports: [CommonModule, CattleDetailModalComponent],
  templateUrl: './cattle-list.component.html',
  styleUrl: './cattle-list.component.scss',
})
export class CattleListComponent implements OnInit {
  // 1. Inyectamos el servicio de datos globales que ya tiene el effect integrado
  private cattleDataService = inject(CattleDataService);

  // 2. Exponemos los signals globales directamente hacia el HTML (.html)
  public cattleList = this.cattleDataService.cattleList;
  public isLoading = this.cattleDataService.isLoading;
  private cattleApi = inject(CattleApiService);
  public tenantService = inject(TenantService);

  // Signals para manejar el estado reactivo
  public totalHeads = signal<number>(0);

  // Variables para el Modal
  public isModalOpen = false;
  public modalAction: 'ALTA' | 'SALUD' | 'PESO' | 'EDITAR' | 'COSTOS' = 'ALTA';
  public selectedRfid = '';
  public selectedId = '';
  public selectedAnimal: any = null;

  async ngOnInit() {
    await this.loadCattle();
  }

  public async loadCattle() {
    this.isLoading.set(true);
    try {
      const data = await this.cattleApi.getAllLivestock();
      this.cattleList.set(data);
      this.totalHeads.set(data.length);
    } catch (error) {
      console.error('Error cargando inventario:', error);
    } finally {
      this.isLoading.set(false);
    }
  }

  public openModal(action: 'ALTA' | 'SALUD' | 'PESO' | 'EDITAR' | 'COSTOS', rfid: string = '', id: string = '', animal: any = null) {
    this.modalAction = action;
    this.selectedRfid = rfid;
    this.selectedId = id;
    this.selectedAnimal = animal;
    this.isModalOpen = true;
  }

  // Cuando el modal se cierra, verificamos si guardó algo para recargar la tabla
  public onModalClose(saved: boolean) {
    this.isModalOpen = false;
    if (saved) {
      this.loadCattle();
    }
  }
}