import { Component, inject, OnInit, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { CattleDetailModalComponent } from '../cattle-detail-modal/cattle-detail-modal.component';
import { CattleApiService } from '@core/services/cattle-api.service';


@Component({
  selector: 'app-cattle-list',
  standalone: true,
  imports: [CommonModule, CattleDetailModalComponent],
  templateUrl: './cattle-list.component.html',
  styleUrl: './cattle-list.component.scss',
})
export class CattleListComponent implements OnInit {
  private cattleApi = inject(CattleApiService);

  // Signals para manejar el estado reactivo
  public cattleList = signal<any[]>([]);
  public totalHeads = signal<number>(0);
  public isLoading = signal<boolean>(true);

  // Variables para el Modal
  public isModalOpen = false;
  public modalAction: 'ALTA' | 'SALUD' | 'PESO' = 'ALTA';
  public selectedRfid = '';
  public selectedId = ''; // Necesitamos el UUID real de la DB para anexar salud/pesos

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

  public openModal(action: 'ALTA' | 'SALUD' | 'PESO', rfid: string = '', id: string = '') {
    this.modalAction = action;
    this.selectedRfid = rfid;
    this.selectedId = id; // Guardamos el UUID
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