import { Component, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { CattleDataService } from '@core/services/cattle-data.service';

@Component({
  selector: 'app-main-dashboard',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './main-dashboard.component.html'
})
export class MainDashboardComponent {
  private dataService = inject(CattleDataService);

  public cattleList = this.dataService.cattleList;
  public totalHeads = this.dataService.totalHeads;
  public criticalAlerts = this.dataService.criticalAlerts;
  public averageAdg = this.dataService.averageAdg;
}