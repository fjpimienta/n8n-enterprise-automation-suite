import { Component, input, computed, ChangeDetectionStrategy, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { NgApexchartsModule } from 'ng-apexcharts';
import { Livestock } from '../../../models/livestock.model';
import { ThemeService } from '@core/services/theme.service';

@Component({
  selector: 'app-reproduccion-dashboard',
  standalone: true,
  imports: [CommonModule, NgApexchartsModule],
  templateUrl: './reproduccion-dashboard.component.html',
  changeDetection: ChangeDetectionStrategy.OnPush
})
export class ReproduccionDashboardComponent {
  public themeService = inject(ThemeService);

  // Recibimos los datos filtrados por Especie desde el Main Dashboard
  public cattleData = input<Livestock[]>([]);

  // 🚀 Blindaje de negocio: Filtramos estrictamente los destinados a REPRODUCCION
  public validReproduccionData = computed(() => {
    return this.cattleData().filter(a => a.business_model === 'REPRODUCCION');
  });

  // 🚀 KPIs del hato reproductor: cabezas, peso promedio y hembras diagnosticadas preñadas
  public stats = computed(() => {
    const data = this.validReproduccionData();
    if (data.length === 0) return { total: 0, avgWeight: '0.00', prenadas: 0 };

    const totalWeight = data.reduce((sum, a) => sum + Number(a.current_weight_kg || 0), 0);

    return {
      total: data.length,
      avgWeight: (totalWeight / data.length).toFixed(2),
      prenadas: data.filter(a => a.last_palpation_result === 'PREÑADA').length
    };
  });

  // 🚀 Configuración Reactiva para la Gráfica de Barras (Composición del hato por Categoría)
  public categoryChartOptions = computed(() => {
    const counts = this.validReproduccionData().reduce((acc, a) => {
      const category = a.category || 'SIN CATEGORÍA';
      acc.set(category, (acc.get(category) ?? 0) + 1);
      return acc;
    }, new Map<string, number>());
    const sorted = [...counts.entries()].sort((a, b) => b[1] - a[1]);

    return {
      series: [{
        name: 'Cabezas',
        data: sorted.map(([, count]) => count)
      }],
      xaxis: {
        categories: sorted.map(([category]) => category),
        labels: { style: { cssClass: 'text-muted font-monospace' } }
      },
      colors: ['#206bc4']
    };
  });
}
