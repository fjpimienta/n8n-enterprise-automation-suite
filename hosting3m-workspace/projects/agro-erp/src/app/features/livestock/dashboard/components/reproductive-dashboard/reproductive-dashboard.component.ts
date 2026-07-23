import { Component, input, computed, ChangeDetectionStrategy, signal, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { NgApexchartsModule } from 'ng-apexcharts';
import { Livestock } from '../../../models/livestock.model';
import { Paginator } from '../../utils/paginator';
import { ThemeService } from '@core/services/theme.service';

@Component({
  selector: 'app-reproductive-dashboard',
  standalone: true,
  imports: [CommonModule, NgApexchartsModule],
  templateUrl: './reproductive-dashboard.component.html',
  changeDetection: ChangeDetectionStrategy.OnPush
})
export class ReproductiveDashboardComponent {
  public themeService = inject(ThemeService);

  public cattleData = input<Livestock[]>([]);

  // 🚀 Blindaje de datos: Mapeo estricto a la columna 'business_model' de PostgreSQL
  public data = computed(() => this.cattleData().filter(a => a.business_model === 'CRIA'));

  // Controladores de Estado de Interfaz
  public isTableCollapsed = signal(true);

  // 🚀 Paginación Reutilizable (composable basado en signals, compartido con main-dashboard)
  public pagination = new Paginator(() => this.data().length);

  // Slice de datos en memoria basado en la página seleccionada
  public paginatedData = computed(() => {
    const startIndex = (this.pagination.currentPage() - 1) * this.pagination.pageSize();
    return this.data().slice(startIndex, startIndex + this.pagination.pageSize());
  });

  public toggleTable() {
    this.isTableCollapsed.update(state => !state);
    this.pagination.reset(); // Reset de seguridad al colapsar/expandir
  }

  // Indicadores Clínicos Derivados
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
