import { Component, inject, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { CattleDataService } from '../../../../core/services/cattle-data.service';

@Component({
  selector: 'app-adg-alerts',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './adg-alerts.component.html',
  styleUrl: './adg-alerts.component.scss',
})
export class AdgAlertsComponent {
  private dataService = inject(CattleDataService);

  // Filtramos la lista maestra para mostrar SOLO excepciones (Mermas y Riesgos)
  public alertList = computed(() =>
    this.dataService.cattleList().filter(animal =>
      animal.estatus_salud === 'CRÍTICO' ||
      animal.estatus_salud === 'PREVENTIVO' ||
      (animal.alerta && animal.alerta !== '')
    )
  );

  public totalAlerts = computed(() => this.alertList().length);
}