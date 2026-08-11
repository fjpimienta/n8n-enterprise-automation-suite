import { Component, input, computed, ChangeDetectionStrategy, signal, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { NgApexchartsModule } from 'ng-apexcharts';
import { Livestock } from '../../../models/livestock.model';
import { Paginator } from '../../utils/paginator';
import { ThemeService } from '@core/services/theme.service';

type SortColumn = 'rfid_siniiga' | 'last_palpation_result' | 'current_gestation_days' | 'condicion_utero';

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

  // 🔎 Búsqueda reactiva de la auditoría (arete SINIIGA o número de fuego)
  public searchQuery = signal<string>('');

  // ↕️ Ordenamiento por columna — por defecto, gestación más avanzada primero
  public sortColumn = signal<SortColumn>('current_gestation_days');
  public sortDirection = signal<'asc' | 'desc'>('desc');

  // 🚀 Paginación Reutilizable (composable basado en signals, compartido con main-dashboard)
  public pagination = new Paginator(() => this.processedData().length);

  // Búsqueda + orden aplicados sobre `data()` antes de paginar
  public processedData = computed(() => {
    const query = this.searchQuery().trim().toLowerCase();
    const filtered = !query
      ? this.data()
      : this.data().filter(animal =>
          animal.rfid_siniiga?.toLowerCase().includes(query) ||
          animal.numero_fuego?.toLowerCase().includes(query)
        );

    const column = this.sortColumn();
    const direction = this.sortDirection() === 'asc' ? 1 : -1;

    return [...filtered].sort((a, b) => {
      if (column === 'current_gestation_days') {
        return (Number(a.current_gestation_days || 0) - Number(b.current_gestation_days || 0)) * direction;
      }
      const valueA = (a[column] ?? '').toString();
      const valueB = (b[column] ?? '').toString();
      return valueA.localeCompare(valueB) * direction;
    });
  });

  // Slice de datos en memoria basado en la página seleccionada
  public paginatedData = computed(() => {
    const startIndex = (this.pagination.currentPage() - 1) * this.pagination.pageSize();
    return this.processedData().slice(startIndex, startIndex + this.pagination.pageSize());
  });

  // 📊 Resumen numérico rápido: distingue "sin diagnóstico" de diagnosticadas PREÑADA/VACIA
  public diagnosisSummary = computed(() => {
    const list = this.data();
    const sinDiagnostico = list.filter(a => !a.last_palpation_result).length;
    const prenadas = list.filter(a => a.last_palpation_result === 'PREÑADA').length;
    const vacias = list.filter(a => a.last_palpation_result === 'VACIA').length;
    return { total: list.length, sinDiagnostico, prenadas, vacias };
  });

  public toggleTable() {
    this.isTableCollapsed.update(state => !state);
    this.pagination.reset(); // Reset de seguridad al colapsar/expandir
  }

  public setSearch(query: string) {
    this.searchQuery.set(query);
    this.pagination.reset();
  }

  public setSort(column: SortColumn) {
    if (this.sortColumn() === column) {
      this.sortDirection.update(dir => (dir === 'asc' ? 'desc' : 'asc'));
    } else {
      this.sortColumn.set(column);
      this.sortDirection.set('asc');
    }
    this.pagination.reset();
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
