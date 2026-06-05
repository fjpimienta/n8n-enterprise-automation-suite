import { Component, inject, signal, computed, OnInit, ChangeDetectionStrategy } from '@angular/core';
import { CommonModule } from '@angular/common';
import { CattleApiService } from '@core/services/cattle-api.service';
import { NgApexchartsModule } from 'ng-apexcharts';
import { ReproductiveDashboardComponent } from '../reproductive-dashboard/reproductive-dashboard.component';
import { EngordaDashboardComponent } from '../engorda-dashboard/engorda-dashboard.component';
import { ExpenseModalComponent } from '../../../expenses/components/expense-modal/expense-modal.component';

@Component({
  selector: 'app-main-dashboard',
  standalone: true,
  imports: [CommonModule, NgApexchartsModule, ReproductiveDashboardComponent, EngordaDashboardComponent, ExpenseModalComponent],
  templateUrl: './main-dashboard.component.html',
  changeDetection: ChangeDetectionStrategy.OnPush
})
export class MainDashboardComponent implements OnInit {
  private cattleApi = inject(CattleApiService);

  public PRECIO_KILO = 65.00;

  public cattleList = signal<any[]>([]);
  public expensesList = signal<any[]>([]);
  public isLoading = signal<boolean>(true);

  // Navegación y Filtros de Trazabilidad Biológica
  public activeTab = signal<'CRIA' | 'ENGORDA'>('CRIA');
  public activeSubTab = signal<'RESUMEN' | 'INVENTARIO' | 'GASTOS'>('RESUMEN');
  public selectedSpecies = signal<string>('TODOS'); // 🚀 Filtro maestro de especie
  public showExpenseModal = signal<boolean>(false);

  // Controladores de Paginación Única
  public currentPage = signal(1);
  public pageSize = signal(10);

  async ngOnInit() {
    await this.loadDashboardData();
  }

  async loadDashboardData() {
    this.isLoading.set(true);
    try {
      const [cattleRaw, expensesRaw] = await Promise.all([
        this.cattleApi.getAllLivestock(),
        this.cattleApi.getExpenses()
      ]);
      this.cattleList.set(cattleRaw);
      this.expensesList.set(expensesRaw);
    } catch (error) {
      console.error('Error en el Data Pipeline del Dashboard:', error);
    } finally {
      this.isLoading.set(false);
    }
  }

  // 🚀 Extracción dinámica de especies existentes en el hato para los selectores de la UI
  public availableSpecies = computed(() => {
    const speciesSet = new Set<string>(this.cattleList().map(a => a.species).filter(Boolean));
    return Array.from(speciesSet);
  });

  // 🚀 Filtrado Jerárquico: Módulo (Tab) + Especie (Selector) con sanitización
  public filteredCattleList = computed(() => {
    const currentTab = this.activeTab();
    const currentSpecies = this.selectedSpecies();

    return this.cattleList().filter(animal => {
      if (!animal.business_model) return false;

      const matchesTab = animal.business_model.trim() === currentTab;
      const matchesSpecies = currentSpecies === 'TODOS' || animal.species === currentSpecies;

      return matchesTab && matchesSpecies;
    });
  });

  // Filtrado de Gastos por Módulo y Especie vinculada
  public filteredExpensesList = computed(() => {
    const currentTab = this.activeTab();
    const currentSpecies = this.selectedSpecies();

    return this.expensesList().filter(expense => {
      // Cruzar con la tabla de ganado si el gasto tiene un livestock_id para saber su especie
      if (expense.livestock_id) {
        const animal = this.cattleList().find(a => a.id === expense.livestock_id);
        if (animal) {
          const matchesTab = animal.business_model === currentTab;
          const matchesSpecies = currentSpecies === 'TODOS' || animal.species === currentSpecies;
          return matchesTab && matchesSpecies;
        }
      }
      return !expense.business_model || expense.business_model === currentTab;
    });
  });

  private currentDataset = computed(() => {
    return this.activeSubTab() === 'GASTOS' ? this.filteredExpensesList() : this.filteredCattleList();
  });

  public totalPages = computed(() => Math.ceil(this.currentDataset().length / this.pageSize()) || 1);

  public showingStart = computed(() => {
    if (this.currentDataset().length === 0) return 0;
    return ((this.currentPage() - 1) * this.pageSize()) + 1;
  });

  public showingEnd = computed(() => Math.min(this.currentPage() * this.pageSize(), this.currentDataset().length));

  public paginatedCattleList = computed(() => {
    if (this.activeSubTab() !== 'INVENTARIO') return [];
    const startIndex = (this.currentPage() - 1) * this.pageSize();
    return this.filteredCattleList().slice(startIndex, startIndex + this.pageSize());
  });

  public paginatedExpensesList = computed(() => {
    if (this.activeSubTab() !== 'GASTOS') return [];
    const startIndex = (this.currentPage() - 1) * this.pageSize();
    return this.filteredExpensesList().slice(startIndex, startIndex + this.pageSize());
  });

  public setTab(tab: 'CRIA' | 'ENGORDA') {
    this.activeTab.set(tab);
    this.activeSubTab.set('RESUMEN');
    this.currentPage.set(1);
  }

  public setSubTab(subTab: 'RESUMEN' | 'INVENTARIO' | 'GASTOS') {
    this.activeSubTab.set(subTab);
    this.currentPage.set(1);
  }

  public setSpecies(species: string) {
    this.selectedSpecies.set(species);
    this.currentPage.set(1);
  }

  public changePageSize(event: Event) {
    this.pageSize.set(Number((event.target as HTMLSelectElement).value));
    this.currentPage.set(1);
  }

  public changePage(delta: number) {
    const newPage = this.currentPage() + delta;
    if (newPage >= 1 && newPage <= this.totalPages()) {
      this.currentPage.set(newPage);
    }
  }

  public biomasaTotal = computed(() => {
    return this.filteredCattleList().reduce((acc, curr) => acc + Number(curr.current_weight_kg || 0), 0);
  });

  public capitalizacionTotal = computed(() => {
    return this.biomasaTotal() * this.PRECIO_KILO;
  });
}