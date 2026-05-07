import { Component, inject, signal, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { CattleDataService } from '../../../../core/services/cattle-data.service';

@Component({
  selector: 'app-main-dashboard',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './main-dashboard.component.html'
})
export class MainDashboardComponent {
  private dataService = inject(CattleDataService);

  public PRECIO_KILO = this.dataService.PRECIO_KILO_MXN;
  public cattleList = this.dataService.cattleList;
  public paricionRate = this.dataService.paricionRate;
  public targetParicion = this.dataService.targetParicion;

  // --- 1. LÓGICA DE PESTAÑAS ---
  public activeTab = signal<'TODOS' | 'CRIA' | 'ENGORDA'>('TODOS');

  public filteredCattleList = computed(() => {
    const currentTab = this.activeTab();
    const list = this.cattleList();
    if (currentTab === 'TODOS') return list;
    return list.filter(animal => animal.modelo === currentTab);
  });

  // --- 2. KPIs DINÁMICOS (Reaccionan al tab seleccionado) ---
  public totalHeads = computed(() => this.filteredCattleList().length);

  public biomasaTotal = computed(() =>
    this.filteredCattleList().reduce((acc, curr) => acc + curr.peso_actual, 0)
  );

  public capitalizacionTotal = computed(() =>
    this.biomasaTotal() * this.PRECIO_KILO
  );

  public criticalAlerts = computed(() =>
    this.filteredCattleList().filter(a => a.estatus_salud === 'CRÍTICO').length
  );

  public averageAdg = computed(() => {
    const list = this.filteredCattleList();
    return list.length ? (list.reduce((acc, curr) => acc + curr.ganancia_diaria_kg, 0) / list.length).toFixed(2) : '0.00';
  });

  public setTab(tab: 'TODOS' | 'CRIA' | 'ENGORDA') {
    this.activeTab.set(tab);
  }
}