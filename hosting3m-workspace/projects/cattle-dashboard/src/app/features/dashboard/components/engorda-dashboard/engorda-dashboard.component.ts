import { Component, input, computed, ChangeDetectionStrategy } from '@angular/core';
import { CommonModule } from '@angular/common';
import { NgApexchartsModule } from 'ng-apexcharts';

@Component({
  selector: 'app-engorda-dashboard',
  standalone: true,
  imports: [CommonModule, NgApexchartsModule],
  templateUrl: './engorda-dashboard.component.html',
  changeDetection: ChangeDetectionStrategy.OnPush
})
export class EngordaDashboardComponent {
  // Recibimos los datos ya filtrados desde el componente padre
  public cattleData = input<any[]>([]);

  // 🚀 Cálculo de KPIs de Engorda (ADG y Peso Promedio)
  public stats = computed(() => {
    const data = this.cattleData();
    if (data.length === 0) return { avgWeight: '0.00', avgAdg: '0.000' };

    const totalWeight = data.reduce((sum, a) => sum + Number(a.current_weight_kg || 0), 0);
    const totalAdg = data.reduce((sum, a) => sum + Number(a.adg_lifetime_kg || 0), 0);

    return {
      avgWeight: (totalWeight / data.length).toFixed(2),
      avgAdg: (totalAdg / data.length).toFixed(3)
    };
  });

  // 🚀 Configuración Reactiva para la Gráfica de Barras (Distribución de Peso)
  public weightChartOptions = computed(() => {
    const data = this.cattleData();
    // Ordenamos de mayor a menor peso para una visualización más limpia
    const sorted = [...data].sort((a, b) => b.current_weight_kg - a.current_weight_kg);

    return {
      series: [{
        name: 'Peso Actual (kg)',
        data: sorted.map(a => Number(a.current_weight_kg || 0))
      }],
      xaxis: {
        // Usamos el número de fuego, o los últimos 4 dígitos del SINIIGA si no hay fuego
        categories: sorted.map(a => a.numero_fuego || `...${a.rfid_siniiga.slice(-4)}`),
        labels: { rotate: -45, style: { cssClass: 'text-muted font-monospace' } }
      },
      colors: ['#206bc4'] // Azul corporativo Tabler
    };
  });
}