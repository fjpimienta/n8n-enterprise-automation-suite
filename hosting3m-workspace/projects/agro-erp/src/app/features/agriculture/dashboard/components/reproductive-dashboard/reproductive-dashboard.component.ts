import { Component, input, computed, ChangeDetectionStrategy, signal } from '@angular/core';
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

  public cattleData = input<any[]>([]);

  // 🚀 Blindaje de datos: Mapeo estricto a la columna 'business_model' de PostgreSQL
  public data = computed(() => this.cattleData().filter(a => a.business_model === 'CRIA'));

  // Controladores de Estado de Interfaz
  public isTableCollapsed = signal(true);

  // 🚀 Sistema de Paginación Reactiva Interno
  public currentPage = signal(1);
  public pageSize = signal(10);

  public totalPages = computed(() => Math.ceil(this.data().length / this.pageSize()) || 1);

  public showingStart = computed(() => {
    if (this.data().length === 0) return 0;
    return ((this.currentPage() - 1) * this.pageSize()) + 1;
  });

  public showingEnd = computed(() => Math.min(this.currentPage() * this.pageSize(), this.data().length));

  // Slice de datos en memoria basado en la página seleccionada
  public paginatedData = computed(() => {
    const startIndex = (this.currentPage() - 1) * this.pageSize();
    return this.data().slice(startIndex, startIndex + this.pageSize());
  });

  public toggleTable() {
    this.isTableCollapsed.update(state => !state);
    this.currentPage.set(1); // Reset de seguridad al colapsar/expandir
  }

  public changePageSize(event: Event) {
    const size = Number((event.target as HTMLSelectElement).value);
    this.pageSize.set(size);
    this.currentPage.set(1);
  }

  public changePage(delta: number) {
    const newPage = this.currentPage() + delta;
    if (newPage >= 1 && newPage <= this.totalPages()) {
      this.currentPage.set(newPage);
    }
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