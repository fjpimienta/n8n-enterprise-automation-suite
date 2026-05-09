import { Component, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { CattleDataService } from '../../../../core/services/cattle-data.service';
// 1. IMPORTAMOS EL COMPONENTE DEL MODAL
import { CattleDetailModalComponent } from '../cattle-detail-modal/cattle-detail-modal.component';

@Component({
  selector: 'app-cattle-list',
  standalone: true,
  // 2. LO AGREGAMOS AL ARREGLO DE IMPORTS
  imports: [CommonModule, CattleDetailModalComponent],
  templateUrl: './cattle-list.component.html',
  styleUrl: './cattle-list.component.scss',
})
export class CattleListComponent {
  private dataService = inject(CattleDataService);

  // Consumimos la lista maestra del servicio centralizado
  public cattleList = this.dataService.cattleList;
  public totalHeads = this.dataService.totalHeads;

  public isModalOpen = false;
  public modalAction: 'ALTA' | 'SALUD' | 'PESO' = 'ALTA';
  public selectedRfid = '';

  public openModal(action: 'ALTA' | 'SALUD' | 'PESO', rfid: string = '') {
    this.modalAction = action;
    this.selectedRfid = rfid;
    this.isModalOpen = true;
  }
}