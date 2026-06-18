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
  // Recibimos los datos filtrados por Especie desde el Main Dashboard
  public cattleData = input<any[]>([]);

  // 🚀 Blindaje de negocio: Filtramos estrictamente los destinados a ENGORDA
  public validEngordaData = computed(() => {
    return this.cattleData().filter(a => a.business_model === 'ENGORDA');
  });

  // 🚀 Cálculo de KPIs de Engorda (ADG y Peso Promedio) por Especie seleccionada
  public stats = computed(() => {
    const data = this.validEngordaData();
    if (data.length === 0) return { avgWeight: '0.00', avgAdg: '0.000' };

    const totalWeight = data.reduce((sum, a) => sum + Number(a.current_weight_kg || 0), 0);
    const totalAdg = data.reduce((sum, a) => sum + Number(a.adg_lifetime_kg || 0), 0);

    return {
      avgWeight: (totalWeight / data.length).toFixed(2),
      avgAdg: (totalAdg / data.length).toFixed(3)
    };
  });

  // 🚀 Configuración Reactiva para la Gráfica de Barras (Distribución de Peso por Especie)
  public weightChartOptions = computed(() => {
    const data = this.validEngordaData();
    const sorted = [...data].sort((a, b) => b.current_weight_kg - a.current_weight_kg);

    return {
      series: [{
        name: 'Peso Actual (kg)',
        data: sorted.map(a => Number(a.current_weight_kg || 0))
      }],
      xaxis: {
        categories: sorted.map(a => a.numero_fuego || `...${a.rfid_siniiga.slice(-4)}`),
        labels: { rotate: -45, style: { cssClass: 'text-muted font-monospace' } }
      },
      colors: ['#206bc4']
    };
  });
}