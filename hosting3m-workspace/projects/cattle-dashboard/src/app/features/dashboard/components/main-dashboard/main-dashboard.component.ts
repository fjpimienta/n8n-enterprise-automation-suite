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
  public expensesList = signal<any[]>([]); // 🚀 Lista de gastos del backend
  public isLoading = signal<boolean>(true);

  // Controladores de Navegación (Soporta la nueva pestaña)
  public activeTab = signal<'CRIA' | 'ENGORDA'>('CRIA');
  public activeSubTab = signal<'RESUMEN' | 'INVENTARIO' | 'GASTOS'>('RESUMEN');
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
      // Carga paralela para optimizar tiempos de respuesta
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

  // Filtrado de ganado
  public filteredCattleList = computed(() => {
    return this.cattleList().filter(animal => animal.business_model === this.activeTab());
  });

  // 🚀 Filtrado de Gastos por Módulo
  public filteredExpensesList = computed(() => {
    return this.expensesList().filter(expense => {
      // Si el gasto no está amarrado a un arete específico (gasto global del rancho),
      // lo mostramos en el historial de ambos módulos para transparencia financiera.
      if (!expense.business_model) return true;

      // Si el gasto sí tiene un arete, lo mostramos solo en el módulo de ese animal.
      return expense.business_model === this.activeTab();
    });
  });

  // Dataset adaptativo según la sub-pestaña seleccionada
  private currentDataset = computed(() => {
    return this.activeSubTab() === 'GASTOS' ? this.filteredExpensesList() : this.filteredCattleList();
  });

  // Algoritmo de Paginación Compartido de Alto Rendimiento
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

  // Setters Reactivos
  public setTab(tab: 'CRIA' | 'ENGORDA') {
    this.activeTab.set(tab);
    this.activeSubTab.set('RESUMEN');
    this.currentPage.set(1);
  }

  public setSubTab(subTab: 'RESUMEN' | 'INVENTARIO' | 'GASTOS') {
    this.activeSubTab.set(subTab);
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