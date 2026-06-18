import { Component, inject, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { CattleDataService } from '@core/services/cattle-data.service';

@Component({
  selector: 'app-adg-alerts',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './adg-alerts.component.html',
  styleUrl: './adg-alerts.component.scss',
})
export class AdgAlertsComponent {
  private dataService = inject(CattleDataService);

  // 🛡️ CORRECCIÓN: Filtrado adaptado a la nomenclatura real de vw_cattle_kpi
  public alertList = computed(() =>
    this.dataService.cattleList().filter(animal =>
      animal.current_status === 'CRÍTICO' ||
      animal.current_status === 'PREVENTIVO' ||
      animal.current_status === 'VACÍA' || // Captura mermas reproductivas si aplica
      (animal.alerta && animal.alerta !== '')
    )
  );

  public totalAlerts = computed(() => this.alertList().length);
}