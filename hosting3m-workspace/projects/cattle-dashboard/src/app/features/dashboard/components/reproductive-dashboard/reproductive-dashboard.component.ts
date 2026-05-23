import { Component, input, computed, ChangeDetectionStrategy } from '@angular/core';
import { CommonModule } from '@angular/common';
import { NgApexchartsModule } from 'ng-apexcharts';

@Component({
  selector: 'app-reproductive-dashboard',
  standalone: true,
  imports: [CommonModule, NgApexchartsModule],
  templateUrl: './reproductive-dashboard.component.html',
  changeDetection: ChangeDetectionStrategy.OnPush
})
export class ReproductiveDashboardComponent {

  // 🚀 Recibe la data ya consultada en la vista principal (Cero consultas SQL redundantes)
  public cattleData = input<any[]>([]);

  // Filtramos estrictamente a CRIA por seguridad, mapeando a la variable 'data' que usa tu HTML
  public data = computed(() => this.cattleData().filter(a => a.modelo === 'CRIA'));

  // Recálculo automático de KPIs
  public stats = computed(() => {
    const list = this.data();
    const total = list.length;
    const prenadas = list.filter(a => a.last_palpation_result === 'PREÑADA').length;
    return {
      total,
      prenadas,
      tasa: total > 0 ? ((prenadas / total) * 100).toFixed(1) : '0.0'
    };
  });

  public getChartOptions = computed(() => {
    const prenadas = this.stats().prenadas;
    const vacias = this.stats().total - prenadas;
    return {
      series: [prenadas, vacias],
      labels: ['Preñadas', 'Vacías'],
      colors: ['#2fb344', '#d63939']
    };
  });
}