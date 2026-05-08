import { Component, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { CattleDataService } from '../../../../core/services/cattle-data.service';

@Component({
  selector: 'app-cattle-list',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './cattle-list.component.html',
  styleUrl: './cattle-list.component.scss',
})
export class CattleListComponent {
  private dataService = inject(CattleDataService);
  
  // Consumimos la lista maestra del servicio centralizado
  public cattleList = this.dataService.cattleList;
  public totalHeads = this.dataService.totalHeads;
}